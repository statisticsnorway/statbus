require "json"
require "log"
require "pg"
require "./config"

# Worker Architecture
#
# The Worker system operates in a single mode:
#
# Background Mode:
#   - Tasks are managed in the worker.tasks table
#   - This Crystal worker process listens for notifications
#   - Suitable for production deployment
#   - Asynchronous processing outside transaction boundaries
#
# For testing:
#   - Tests use transaction ABORT to roll back changes
#   - No special mode needed for testing
#   - Tasks are created but rolled back with the test transaction
#   - Tests must manually call worker.process_tasks() to simulate worker processing:
#     ```sql
#     BEGIN;
#     -- Create test data and trigger worker tasks
#     INSERT INTO some_table VALUES (...);
#     -- Manually process tasks that would normally be handled by the worker
#     SELECT * FROM worker.process_tasks();
#     -- Verify results
#     SELECT * FROM affected_table WHERE ...;
#     -- Roll back all changes including tasks
#     ROLLBACK;
#     ```
#
# The Worker handles processing of database tasks by tracking changes
# in the underlying tables (establishment, legal_unit, enterprise, etc).
# Architecture flow:
#
# System Architecture:
# +----------------+     +-----------------+     +------------------+     +------------------+
# |  PostgreSQL DB |     |    Worker      |     |    Command       |     |    Task         |
# |  NOTIFY        | --> |    Listener    | --> |    Channel       | --> |    Processor    |
# |  worker_tasks  |     |(PG.connect_listen)|   | (bounded queue)  |     |    (fiber)      |
# +----------------+     +-----------------+     +------------------+     +------------------+
#
# Components:
# 1. PostgreSQL Tasks Table:
#    - Database stores tasks in worker.tasks table
#    - Commands: refresh_derived_data, check_table, deleted_row
#    - Each task has typed columns for parameters
#
# 2. Worker Listener:
#    - Runs using PG.connect_listen for notifications
#    - Triggers processing when notified of new tasks
#    - Simple notification without payload
#
# 3. Command Queue:
#    - Channel-based queue for thread-safe command passing
#    - Buffers commands between listener and processor
#
# 4. Task Processor:
#    - Runs in dedicated fiber
#    - Processes tasks in batches
#    - Handles errors per task without affecting others
#    - Records task status and error messages
#
# Error Handling:
# - Task processing errors are recorded in the tasks table
# - Failed tasks don't block other tasks from processing
# - Detailed error messages are available for debugging
module Statbus
  class Worker
    @log : ::Log
    @config : Config
    @timer_queue = Channel(Time).new(10)                # Queue for scheduled tasks
    @queue_processors = {} of String => Channel(Symbol) # Map of queue names to processor channels with large buffer
    @available_queues = [] of String                    # List of available queues

    def initialize(config)
      @config = config

      # Configure logging based on environment variables
      # This will respect LOG_LEVEL env var by default
      Log.setup_from_env(
        default_level: ENV["VERBOSE"]? == "1" ? Log::Severity::Trace : ENV["DEBUG"]? == "1" ? Log::Severity::Debug : Log::Severity::Info
      )

      @log = ::Log.for("worker")

      # Log startup information
      if ENV["VERBOSE"]? == "1"
        @log.info { "Verbose logging enabled" }
      elsif ENV["DEBUG"]? == "1"
        @log.info { "Debug logging enabled" }
      end

      # Log environment settings at debug level
      @log.debug { "Environment settings detected:" }
      @log.debug { "  VERBOSE=#{ENV["VERBOSE"]? || "0"}" }
      @log.debug { "  DEBUG=#{ENV["DEBUG"]? || "0"}" }
    end

    # Initialize queue processors based on available queues
    private def initialize_queue_processors
      DB.connect(@config.connection_string) do |db|
        # Get all available queues from the database
        queues = db.query_all "SELECT DISTINCT queue FROM worker.command_registry", as: String

        @available_queues = queues
        @log.info { "Found #{queues.size} queue(s): #{queues.join(", ")}" }

        # Create a processor channel for each queue with large buffer
        queues.each do |queue|
          @queue_processors[queue] = Channel(Symbol).new(8192)
          @log.debug { "Created processor channel for queue: #{queue}" }
        end
      end
    rescue ex
      @log.error { "Failed to initialize queue processors: #{ex.message}" }
      @log.error { ex.backtrace.join("\n") }
    end

    # Start a processing fiber for each queue
    private def start_queue_processors
      @queue_processors.each do |queue, channel|
        @log.info { "Starting processor for queue: #{queue}" }
        spawn process_queue_loop(queue, channel)
      end
    end

    def run
      Signal::INT.trap do
        @log.info { "Received CTRL-C, shutting down..." }
        @timer_queue.close

        # Close all queue processor channels
        @queue_processors.each do |queue, channel|
          channel.close
        end

        exit
      end

      # Wait for worker schema to be ready before starting processing
      wait_for_worker_schema

      # Initialize and start queue processors
      initialize_queue_processors
      start_queue_processors

      # Start timer checking fiber
      spawn check_scheduled_tasks_loop

      # Queue initial processing on startup for all queues
      @queue_processors.each do |queue, channel|
        channel.send(:process)
      end

      # Main connection loop with retry logic
      max_retries = 10
      retry_count = 0
      retry_delay = 1.seconds

      loop do
        begin
          @log.debug { "Connecting to database at #{@config.postgres_host}:#{@config.postgres_port}..." }

          # First verify we can connect to the database
          DB.connect(@config.connection_string) do |db|
            version = db.query_one("SELECT version()", as: String)
            @log.debug { "Database connection verified: #{version}" }

            # Check if worker schema exists
            schema_exists = db.query_one? "SELECT EXISTS (
                                            SELECT FROM pg_namespace
                                            WHERE nspname = 'worker'
                                          )", as: Bool

            if schema_exists
              @log.debug { "Worker schema exists" }
            else
              @log.info { "Worker schema doesn't exist yet. Waiting for migrations to run..." }
            end
          end

          # Listen for notifications in a background thread
          connection = PG.connect_listen(@config.connection_string, channels: ["worker_tasks", "worker_queue_change"], blocking: true) do |notification|
            if notification.channel == "worker_tasks"
              # Get the queue from the notification payload
              queue_name = notification.payload.presence

              # If a specific queue was mentioned in the notification
              if queue_name && @queue_processors.has_key?(queue_name)
                @log.debug { "Received notification for specific queue: #{queue_name}" }
                @queue_processors[queue_name].send(:process)
              else
                # Notify all queue processors if no specific queue or unknown queue
                @queue_processors.each do |queue, channel|
                  channel.send(:process)
                end
              end
            elsif notification.channel == "worker_queue_change"
              # When queue change notification received, check for new queues
              @log.info { "Queue change detected, checking for new queues..." }
              check_for_new_queues
            end
          end

          # Log successful connection
          @log.debug { "Connected to database at #{@config.postgres_host}:#{@config.postgres_port}" }

          # Process any pending tasks immediately after connecting for all queues
          @queue_processors.each do |queue, channel|
            channel.send(:process)
          end

          # The connection is already in listening mode and will block in the background
          # Just wait indefinitely until an exception occurs or the program is terminated
          sleep

          # If we get here, the connection was closed normally
          @log.info { "Database connection closed, reconnecting..." }
          retry_count = 0
        rescue ex : DB::ConnectionRefused | Socket::ConnectError
          retry_count += 1
          if retry_count <= max_retries
            @log.error { "Database connection failed (attempt #{retry_count}/#{max_retries}): #{ex.message}" }
            @log.error { "Connection string: postgres://#{@config.postgres_user}:***@#{@config.postgres_host}:#{@config.postgres_port}/#{@config.postgres_db}" }
            @log.info { "Retrying in #{retry_delay} seconds..." }
            sleep(retry_delay)
            # Exponential backoff with a cap
            retry_delay = {retry_delay * 2, 60.seconds}.min
          else
            @log.fatal { "Failed to connect to database after #{max_retries} attempts, exiting" }
            @timer_queue.close
            @queue_processors.each do |_, channel|
              channel.close
            end
            exit(1)
          end
        rescue ex
          @log.error { "Unexpected error: #{ex.message}" }
          @log.error { ex.backtrace.join("\n") }
          sleep(5.seconds)
        end
      end
    end

    # Continuously check for scheduled tasks
    private def check_scheduled_tasks_loop
      loop do
        begin
          next_scheduled, queue = find_next_scheduled_task

          if next_scheduled
            # Calculate time until next task
            now = Time.utc
            time_until_next = next_scheduled - now

            if time_until_next.total_seconds > 0
              @log.debug { "Next scheduled task at #{next_scheduled} for queue #{queue || "unknown"}, waiting #{time_until_next.total_seconds.round(2)} seconds" }

              # Wait for the scheduled time or until interrupted
              select
              when @timer_queue.receive
                # A new scheduled task was found, restart the loop
                @log.debug { "Timer interrupted by new scheduled task" }
              when timeout(time_until_next)
                # Time to process the scheduled task
                @log.debug { "Timer expired, processing scheduled tasks for queue #{queue || "unknown"}" }

                # If we know which queue the task belongs to, notify only that processor
                if queue && @queue_processors.has_key?(queue)
                  @log.debug { "Notifying specific queue processor: #{queue}" }
                  @queue_processors[queue].send(:process)
                else
                  # Otherwise notify all queue processors
                  @log.debug { "Notifying all queue processors" }
                  @queue_processors.each do |q, channel|
                    channel.send(:process)
                  end
                end
              end
            else
              # Task is due now or overdue
              if queue && @queue_processors.has_key?(queue)
                @log.debug { "Task overdue for queue #{queue}, notifying specific processor" }
                @queue_processors[queue].send(:process)
              else
                # Notify all queue processors if queue is unknown
                @log.debug { "Task overdue for unknown queue, notifying all processors" }
                @queue_processors.each do |q, channel|
                  channel.send(:process)
                end
              end
              sleep(1.seconds) # Prevent tight loop
            end
          else
            # No scheduled tasks, wait for a while
            sleep(60.seconds) # Check every minute
          end
        rescue Channel::ClosedError
          @log.info { "Timer channel closed, shutting down timer loop" }
          break
        rescue ex
          @log.error { "Error in scheduled task checker: #{ex.message}" }
          sleep(10.seconds) # Wait a bit before retrying
        end
      end
    end

    # Wait for worker schema and tables to be ready
    private def wait_for_worker_schema
      @log.info { "Checking for worker schema and tables..." }

      loop do
        schema_exists = false
        tables_exist = false

        begin
          DB.connect(@config.connection_string) do |db|
            # Check if worker schema exists
            schema_exists = db.query_one? "SELECT EXISTS (
                                           SELECT FROM pg_namespace
                                           WHERE nspname = 'worker'
                                         )", as: Bool

            if schema_exists
              # Check if worker tables exist
              tables_exist = db.query_one? "SELECT EXISTS (
                                           SELECT FROM pg_tables
                                           WHERE schemaname = 'worker' AND tablename = 'tasks'
                                         )", as: Bool
            end
          end

          if schema_exists && tables_exist
            @log.info { "Worker schema and tables are ready" }
            return
          else
            if !schema_exists
              @log.info { "Worker schema doesn't exist yet. Waiting for migrations to run..." }
            elsif !tables_exist
              @log.info { "Worker schema exists but tables don't exist yet. Waiting for migrations to run..." }
            end
            sleep(5.seconds)
          end
        rescue ex
          @log.error { "Error checking for worker schema: #{ex.message}" }
          sleep(5.seconds)
        end
      end
    end

    # Find the next scheduled task
    private def find_next_scheduled_task : {Time?, String?}
      DB.connect(@config.connection_string) do |db|
        result = db.query_one? "SELECT
                                 MIN(t.scheduled_at) AS next_scheduled_at,
                                 cr.queue
                               FROM worker.tasks t
                               JOIN worker.command_registry cr ON t.command = cr.command
                               WHERE t.status = 'pending'
                                 AND t.scheduled_at IS NOT NULL
                                 AND t.scheduled_at > now()
                               GROUP BY cr.queue
                               ORDER BY next_scheduled_at
                               LIMIT 1",
          as: {Time?, String?}

        return result || {nil, nil}
      end
    rescue DB::ConnectionRefused | Socket::ConnectError
      @log.error { "Database connection failed while checking scheduled tasks" }
      sleep(5.seconds) # Wait before retrying
      return {nil, nil}
    rescue ex
      @log.error { "Error finding next scheduled task: #{ex.message}" }
      @log.error { ex.backtrace.join("\n") }
      return {nil, nil}
    end

    # Queue-specific processing loop
    private def process_queue_loop(queue : String, channel : Channel(Symbol))
      @log.info { "Starting processing fiber for queue: #{queue}" }
      loop do
        begin
          command = channel.receive

          if command == :process
            @log.debug { "Processing tasks for queue: #{queue}" }
            process_tasks(queue)
          end

          # Check for new scheduled tasks after processing
          check_for_new_scheduled_tasks
        rescue Channel::ClosedError
          @log.info { "Queue channel closed, shutting down #{queue} process loop" }
          break
        rescue ex
          @log.error { "Error in #{queue} process loop: #{ex.message}" }
          sleep(1.seconds) # Prevent tight loop on error
        end
      end
    end

    # Check for new queues and create processors for them
    private def check_for_new_queues
      begin
        DB.connect(@config.connection_string) do |db|
          # Get all available queues from the database
          new_queues = db.query_all "SELECT DISTINCT queue FROM worker.command_registry", as: String

          # Find queues that don't have processors yet
          new_queues.each do |queue|
            unless @queue_processors.has_key?(queue)
              @log.info { "New queue detected: #{queue}" }
              @queue_processors[queue] = Channel(Symbol).new(100)
              spawn process_queue_loop(queue, @queue_processors[queue])
              @available_queues << queue
            end
          end

          # Log current queues
          @log.debug { "Current queues: #{@available_queues.join(", ")}" }
        end
      rescue ex
        @log.error { "Error checking for new queues: #{ex.message}" }
      end
    end

    # Check if any new scheduled tasks have been added
    private def check_for_new_scheduled_tasks
      next_scheduled, queue = find_next_scheduled_task
      if next_scheduled
        # Notify the timer checker about the new task
        @timer_queue.send(next_scheduled)

        # If we know which queue the task belongs to, notify only that processor
        if queue && @queue_processors.has_key?(queue)
          @log.debug { "New scheduled task for queue #{queue}, notifying specific processor" }
          @queue_processors[queue].send(:process)
        else
          # Otherwise notify all queue processors
          @log.debug { "New scheduled task for unknown queue, notifying all processors" }
          @queue_processors.each do |q, channel|
            channel.send(:process)
          end
        end
      end
    end

    # Process pending tasks for a specific queue
    private def process_tasks(queue : String)
      start_time = Time.monotonic
      begin
        DB.connect(@config.connection_string) do |db|
          # Query worker.process_tasks() with named columns for better documentation
          results = db.query_all "SELECT
                                    id,            -- The task ID
                                    command,       -- The command that was executed
                                    queue,      -  -- The task queue
                                    duration_ms,   -- How long the task took to process in milliseconds
                                    success,       -- Whether the task succeeded (TRUE) or failed (FALSE)
                                    error_message  -- Error message if task failed, NULL otherwise
                                  FROM worker.process_tasks(p_queue := $1)",
            queue,
            as: {Int64, String, String, PG::Numeric, Bool, String?}

          if results.empty?
            @log.debug { "No tasks to process for queue: #{queue}" }
          else
            @log.debug { "Processed #{results.size} tasks for queue: #{queue}" }
            results.each do |id, command, queue, duration, success, error|
              duration_float = duration.to_f
              if success
                @log.debug { "Task #{id} (#{command}) completed in #{duration_float.round(2)}ms" }
              else
                @log.error { "Task #{id} (#{command}) failed after #{duration_float.round(2)}ms: #{error}" }
              end
            end

            # Only log at INFO level if there were errors
            if results.any? { |_, _, _, _, success, _| !success }
              @log.info { "Processed #{results.size} tasks with errors for queue: #{queue}" }
            end

            # Schedule a task cleanup if we processed tasks
            db.exec "SELECT worker.enqueue_task_cleanup()"
          end
        end
      rescue DB::ConnectionRefused | Socket::ConnectError
        @log.error { "Database connection failed while processing tasks for queue: #{queue}" }
        # Don't log the full stack trace for connection issues
        sleep(5.seconds) # Wait before retrying
      rescue ex
        @log.error { "Error processing tasks for queue #{queue}: #{ex.message}" }
        @log.error { ex.backtrace.join("\n") }
      ensure
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i
        @log.debug { "Task processing for queue #{queue} completed in #{duration_ms}ms" }
      end
    end
  end
end
