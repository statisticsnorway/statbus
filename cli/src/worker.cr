require "json"
require "log"
require "pg"
require "./config"

# Worker Architecture
# The Worker handles asynchronous processing of database commands through PostgreSQL notifications.
# Architecture flow:
#
# +----------------+     +-----------------+     +------------------+     +------------------+
# |  PostgreSQL DB |     | Notification    |     |   Command        |     |    Command       |
# |  NOTIFY worker | --> | Listener        | --> |   Channel        | --> |    Processor     |
# +----------------+     | (background)    |     | (bounded queue)  |     |    (fiber)       |
#                       +-----------------+     +------------------+     +------------------+
#
# Components:
# 1. PostgreSQL Notifications:
#    - Database sends NOTIFY events with JSON payloads
#    - Supported commands: ping, refresh_materialized_views, update_statistical_unit, check_table
#
# 2. NotificationListener:
#    - Runs in background using PG.connect_listen
#    - Parses JSON payloads into typed Command objects
#    - Sends valid commands to the command queue channel
#
# 3. Command Queue:
#    - Channel-based queue for thread-safe command passing
#    - Buffers commands between listener and processor
#
# 4. CommandProcessor:
#    - Runs in dedicated fiber
#    - Batches commands with 100ms collection window
#    - Processes batches sequentially in background fibers
#    - Maintains processing readiness state
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
      # Initialize tables needed for processing
      DB.connect(@config.connection_string) do |db|
        command_check_table_setup(db)
      end

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

        cmd = case payload["command"].as_s
              when "ping"                       then CommandPing.new(payload["ident"].as_i64)
              when "refresh_materialized_views" then CommandRefreshMaterializedViews.new
              when "update_statistical_unit"
                CommandUpdateStatisticalUnit.new(
                  payload["unit_type"].as_s,
                  payload["unit_id"].as_i64
                )
              when "check_table"
                CommandCheckTable.new(
                  payload["table_name"].as_s,
                  payload["transaction_id"].as_i64
                )
              else
                @log.error { "Unknown command: #{payload}" }
                nil
              end

        @command_queue.send(cmd) if cmd
      rescue ex
        @log.error { "Error processing notification #{notification}: #{ex}" }
      end
    end

    private def receive_command_then_batch_and_process_batch
      commands = [] of Command
      ready = true
      done = Channel(Nil).new
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
          #  in CommandUpdateStatisticalUnit
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
        when done.receive
          ready = true
          # The batch processing finished, and a new batch may be processed.
        when timeout(100.milliseconds)
          # If there is no activity then the timeout allows running commands collected so far.
        end
        if ready && !commands.empty?
          ready = false
          # Process batch in the background, so commands can still be collected.
          batch = commands.dup
          spawn do
            batch.each { |cmd| process_command(cmd) }
            done.send(nil) # Signal batch completion
          end
          commands.clear
        end
      end
    end

    private def process_command(cmd)
      @log.info { "Processing #{cmd.class.name}" }
      start_time = Time.monotonic
      begin
        DB.connect(@config.connection_string) do |db|
          case cmd
          in CommandPing
            db.exec "SELECT pg_notify('pong', $1);", cmd.ident
          in CommandRefreshMaterializedViews
            db.exec "SELECT public.statistical_unit_refresh_now();"
          in CommandUpdateStatisticalUnit
            command_update_statistical_unit(db, cmd)
          in CommandCheckTable
            command_check_table(db, cmd)
          end
        end
      rescue ex
        @log.error { "Error processing command #{cmd.class.name}: #{ex.message}" }
      ensure
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i
        @log.info { "done (#{duration_ms}ms)" }
      end
    end

    private def command_check_table_setup(db)
      db.exec <<-SQL
        CREATE SCHEMA IF NOT EXISTS "worker";
      SQL
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS worker.last_processed (
          table_name text PRIMARY KEY,
          transaction_id bigint NOT NULL
        );
      SQL

      # Create or replace the trigger function
      db.exec <<-SQL
        CREATE OR REPLACE FUNCTION worker.notify_worker_about_changes()
        RETURNS trigger
        LANGUAGE plpgsql
        AS $function$
        BEGIN
          PERFORM pg_notify(
            'worker',
            json_build_object(
              'command', 'check_table',
              'table_name', TG_TABLE_NAME,
              'transaction_id', txid_current()
            )::text
          );
          RETURN NULL;
        END;
        $function$;
      SQL

      # Create triggers for all tables that need change tracking
      db.exec <<-SQL
        DO $$
        DECLARE
          table_name text;
        BEGIN
          FOR table_name IN 
            SELECT unnest(ARRAY[
              'legal_unit',
              'establishment',
              'activity',
              'sector',
              'location',
              'contact',
              'stat_for_unit'
            ])
          LOOP
            IF NOT EXISTS (
              SELECT 1 FROM pg_trigger 
              WHERE tgname = table_name || '_changes_trigger'
              AND tgrelid = ('public.' || table_name)::regclass
            ) THEN
              EXECUTE format(
                'CREATE TRIGGER %I
                AFTER INSERT OR UPDATE OR DELETE ON public.%I
                FOR EACH STATEMENT
                EXECUTE FUNCTION worker.notify_worker_about_changes()',
                table_name || '_changes_trigger',
                table_name
              );
            END IF;
          END LOOP;
        END;
        $$;
      SQL
    end

    private def command_check_table(db, cmd : CommandCheckTable)
      # Get current transaction ID to mark processing point
      current_txid = db.query_one("SELECT txid_current()", as: Int64)

      # Extract IDs based on table type
      unit_id_columns = case cmd.table_name
                        when "legal_unit"
                          "id AS legal_unit_id, NULL::INT AS establishment_id"
                        when "establishment"
                          "NULL::INT AS legal_unit_id, id AS establishment_id"
                        else
                          "legal_unit_id, establishment_id"
                        end

      # Find changed rows since last processing
      changed_rows = db.query_all <<-SQL, cmd.transaction_id, as: {id: Int32, legal_unit_id: Int32?, establishment_id: Int32?, valid_after: Time?, valid_from: Time?, valid_to: Time?}
        SELECT id
             , #{unit_id_columns}
             , CASE WHEN valid_after = '-infinity' THEN NULL ELSE valid_after END AS valid_after
             , CASE WHEN valid_from = '-infinity' THEN NULL ELSE valid_from END AS valid_from
             , CASE WHEN valid_to = 'infinity' THEN NULL ELSE valid_to END AS valid_to
        FROM #{cmd.table_name} 
        WHERE age($1::xid) >= age(xmin)
        ORDER BY id;
      SQL

      # Process changed rows (implement specific processing here)
      changed_rows.each do |row|
        @log.info { "Processing changed row in #{cmd.table_name} (id: #{row[:id]},legal_unit_id: #{row[:legal_unit_id]}, establishment_id: #{row[:establishment_id]}, valid_from: #{row[:valid_from]}, valid_to: #{row[:valid_to]})" }
        # Add specific row processing logic here
      end

      # Update last processed transaction
      db.exec <<-SQL, cmd.table_name, current_txid
        INSERT INTO worker.last_processed (table_name, transaction_id)
        VALUES ($1, $2)
        ON CONFLICT (table_name) 
        DO UPDATE SET transaction_id = EXCLUDED.transaction_id;
      SQL
    end

    private def command_update_statistical_unit(db, cmd : CommandUpdateStatisticalUnit)
      db.exec "SELECT public.statistical_unit_refresh_now();"
    end

    record CommandPing, ident : Int64
    record CommandRefreshMaterializedViews
    record CommandUpdateStatisticalUnit, unit_type : String, unit_id : Int64
    record CommandCheckTable, table_name : String, transaction_id : Int64
    alias Command = CommandPing |
                    CommandRefreshMaterializedViews | CommandUpdateStatisticalUnit | CommandCheckTable
  end
end
