require "json"
require "log"
require "pg"
require "./config"

# Worker Architecture
#
# The Worker system can operate in two modes:
#
# 1. Background Mode (Default):
#    - Commands are sent via PostgreSQL NOTIFY/LISTEN
#    - This Crystal worker process listens for notifications
#    - Suitable for production deployment
#    - Asynchronous processing outside transaction boundaries
#    - Set with: SELECT worker.mode('background');
#
# 2. Foreground Mode:
#    - Commands execute synchronously in PL/pgSQL
#    - No Crystal worker process needed
#    - Suitable for testing since commands run in same transaction
#    - Changes rollback with test transaction ABORT
#    - Set with: SELECT worker.mode('foreground');
#
# The Worker handles processing of database commands through PostgreSQL NOTIFY/LISTEN.
# It maintains materialized views and denormalized tables for statistical units by tracking changes
# in the underlying tables (establishment, legal_unit, enterprise, etc).
# Architecture flow:
#
# System Architecture:
# +----------------+     +-----------------+     +------------------+     +------------------+
# |  PostgreSQL DB |     |    Worker      |     |    Command      |     |    Command      |
# |  NOTIFY worker | --> |    Listener    | --> |    Queue        | --> |    Processor    |
# +----------------+     | (PG.connect)   |     | (Channel<JSON>) |     |    (Fiber)      |
#                       +-----------------+     +------------------+     +------------------+
#
# Components:
# 1. PostgreSQL Notifications:
#    - Database sends NOTIFY events with JSON payloads
#    - Commands: ping, refresh_materialized_views, check_table, deleted_row
#    - Payload contains command type and parameters
#
# 2. Worker Listener:
#    - Runs using PG.connect_listen for background notifications
#    - Validates and parses JSON payloads
#    - Sends valid commands to queue channel
#
# 3. Command Queue:
#    - Uses Crystal Channel for thread-safe command passing
#    - Buffers JSON::Any commands between listener and processor
#    - Provides backpressure when processing is slow
#
# 4. Command Processor:
#    - Runs in dedicated fiber for background processing
#    - Batches commands with 300ms collection window
#    - Processes each command through worker.process() function
#    - Handles errors per command without affecting others
#
# Error Handling:
# - JSON parsing errors are logged but don't crash the worker
# - Invalid commands are logged and skipped
# - Database processing errors are contained within command processing
module Statbus
  class Worker
    @log : ::Log
    @config : Config
    @command_queue = Channel(Command).new

    def initialize(config)
      @config = config
      @log = ::Log.for("worker")
      # Log.setup do |c|
      # # TODO: Log to Seq using SEQ_SERVER_URL SEQ_API_KEY in ENV[""]
      #   backend = Log::IOBackend.new
      #
      #   c.bind "*", :warn, backend
      #   c.bind "db.*", :debug, backend
      #   c.bind "*", :error, ElasticSearchBackend.new("http://localhost:9200")
      # end
      Log.setup_from_env
    end

    def run
      # Start processing in background fiber
      spawn { receive_command_then_batch_and_process_batch }

      Signal::INT.trap do
        @log.info { "Received CTRL-C, shutting down..." }
        exit
      end

      # Listen for notifications in a background thread
      connection = PG.connect_listen(@config.connection_string, channels: ["worker"], blocking: true) do |notification|
        receive_notification_and_queue_command(notification)
      end
    end

    private def receive_notification_and_queue_command(notification : PQ::Notification)
      begin
        payload = JSON.parse(notification.payload)
        command = payload["command"]?.try(&.as_s)
        if command
          @command_queue.send(payload)
        else
          @log.error { "Invalid command payload: #{payload}" }
        end
      rescue ex
        @log.error { "Error processing notification #{notification}: #{ex}" }
      end
    end

    private def receive_command_then_batch_and_process_batch
      commands = [] of Command
      ready = true
      waited_once_for_timeout_at_the_start_of_batch = false
      processed_batch = Channel(Nil).new
      loop do
        # Collect commands with timeout
        select
        when new_cmd = @command_queue.receive
          # TODO: Complete type safe cast and comparison
          # commands = commands.reduce([] of Command) do |acc, old_cmd|
          #  case [old_cmd,new_cmd]
          #  in [CommandPing, CommandPing]
          #    # Deduplicate pings
          #    acc.any? { |c| c.is_a?(CommandPing) && c.ident == old_cmd.ident } ? acc : acc << old_cmd
          #  in CommandRefreshMaterializedViews
          #  in CommandCheckTable
          #    # Keep only the latest transaction ID per table
          #    existing = acc.find { |c| c.is_a?(CommandCheckTable) && c.table_name == old_cmd.table_name }
          #    if existing && existing.transaction_id >= old_cmd.transaction_id
          #      acc
          #    else
          #      acc.reject(&.is_a?(CommandCheckTable)) << old_cmd
          #    end
          #  end
          # end
          commands << new_cmd
        when processed_batch.receive
          ready = true
          # The batch processing finished, and a new batch may be processed.
        when timeout(300.milliseconds)
          # If there is no activity then the timeout allows running commands collected so far.
          if !commands.empty?
            waited_once_for_timeout_at_the_start_of_batch = true
          end
        end
        if ready && waited_once_for_timeout_at_the_start_of_batch && !commands.empty?
          ready = false
          waited_once_for_timeout_at_the_start_of_batch = false
          # Process batch in the background, so commands can still be collected.
          batch = commands.dup
          @log.debug { "Processing batch #{batch.inspect}" }
          spawn do
            batch.each { |cmd| process_command(cmd) }
            # Process any detected changes
            processed_batch.send(nil) # Signal batch completion
          end
          commands.clear
        end
      end
    end

    private def process_command(payload : JSON::Any)
      @log.info { "Processing #{payload.inspect}" }
      start_time = Time.monotonic
      begin
        DB.connect(@config.connection_string) do |db|
          db.exec "SELECT worker.process($1::jsonb);", payload.to_json
        end
      rescue ex
        @log.error { "Error processing command #{payload.inspect}: #{ex.message}" }
      ensure
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i
        @log.info { "done (#{duration_ms}ms)" }
      end
    end

    alias Command = JSON::Any
  end
end
