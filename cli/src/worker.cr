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
    @command_queue = Channel({Symbol, String}).new(8192) # Bounded queue with priority
    @timer_queue = Channel(Time).new(10)     # Queue for scheduled tasks

    def initialize(config)
      @config = config
      
      # Configure logging based on environment variables
      # This will respect LOG_LEVEL env var by default
      Log.setup_from_env(
        default_level: ENV["VERBOSE"]? == "1" ? Log::Severity::Trace : 
                       ENV["DEBUG"]? == "1" ? Log::Severity::Debug : 
                       Log::Severity::Info
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

    def run
      Signal::INT.trap do
        @log.info { "Received CTRL-C, shutting down..." }
        @command_queue.close
        @timer_queue.close
        exit
      end

      # Wait for worker schema to be ready before starting processing
      wait_for_worker_schema

      # Start processing fibers for each priority
      spawn process_commands_loop("high")
      spawn process_commands_loop("medium")
      spawn process_commands_loop("low")

      # Start timer checking fiber
      spawn check_scheduled_tasks_loop

      # Queue initial processing on startup for all priorities
      @command_queue.send({:process, "high"})
      @command_queue.send({:process, "medium"})
      @command_queue.send({:process, "low"})

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
          connection = PG.connect_listen(@config.connection_string, channels: ["worker_tasks"], blocking: true) do |notification|
            # When notification received, queue a processing command
            @command_queue.send({:process,"all"})
          end
          
          # Log successful connection
          @log.debug { "Connected to database at #{@config.postgres_host}:#{@config.postgres_port}" }
          
          # Process any pending tasks immediately after connecting
          @command_queue.send({:process, "all"})
          
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
            @command_queue.close
            @timer_queue.close
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
          next_scheduled = find_next_scheduled_task

          if next_scheduled
            # Calculate time until next task
            now = Time.utc
            time_until_next = next_scheduled - now

            if time_until_next.total_seconds > 0
              @log.debug { "Next scheduled task at #{next_scheduled}, waiting #{time_until_next.total_seconds.round(2)} seconds" }

              # Wait for the scheduled time or until interrupted
              select
              when @timer_queue.receive
                # A new scheduled task was found, restart the loop
                @log.debug { "Timer interrupted by new scheduled task" }
              when timeout(time_until_next)
                # Time to process the scheduled task
                @log.debug { "Timer expired, processing scheduled tasks" }
                @command_queue.send({:process, "all"})
              end
            else
              # Task is due now or overdue
              @command_queue.send({:process,"all"})
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
    private def find_next_scheduled_task : Time?
      DB.connect(@config.connection_string) do |db|
        result = db.query_one? "SELECT
                                 MIN(scheduled_at) AS next_scheduled_at
                               FROM worker.tasks
                               WHERE status = 'pending'
                                 AND scheduled_at IS NOT NULL
                                 AND scheduled_at > now()",
          as: Time?

        return result
      end
    rescue DB::ConnectionRefused | Socket::ConnectError
      @log.error { "Database connection failed while checking scheduled tasks" }
      sleep(5.seconds) # Wait before retrying
      return nil
    rescue ex
      @log.error { "Error finding next scheduled task: #{ex.message}" }
      @log.error { ex.backtrace.join("\n") }
      return nil
    end

    # Main processing loop that runs in a separate fiber for each priority
    private def process_commands_loop(priority : String)
      @log.info { "Starting processing fiber for #{priority} priority tasks" }
      loop do
        begin
          command, cmd_priority = @command_queue.receive

          # Only process if the command is for this priority or for all priorities
          if command == :process && (cmd_priority == priority || cmd_priority == "all")
            @log.debug { "Processing #{priority} priority tasks" }
            process_tasks(priority)
          end

          # Check for new scheduled tasks after processing
          check_for_new_scheduled_tasks
        rescue Channel::ClosedError
          @log.info { "Command channel closed, shutting down #{priority} process loop" }
          break
        rescue ex
          @log.error { "Error in #{priority} process command loop: #{ex.message}" }
          sleep(1.seconds) # Prevent tight loop on error
        end
      end
    end

    # Check if any new scheduled tasks have been added
    private def check_for_new_scheduled_tasks
      next_scheduled = find_next_scheduled_task
      if next_scheduled
        # Notify the timer checker about the new task
        @timer_queue.send(next_scheduled)
        
        # Notify all priority queues to check for new tasks
        @command_queue.send({:process, "all"})
      end
    end

    # Process pending tasks for a specific priority
    private def process_tasks(priority : String)
      start_time = Time.monotonic
      begin
        DB.connect(@config.connection_string) do |db|
          # Query worker.process_tasks() with named columns for better documentation
          results = db.query_all "SELECT
                                    id,            -- The task ID
                                    command,       -- The command that was executed
                                    priority,      -- The task priority
                                    duration_ms,   -- How long the task took to process in milliseconds
                                    success,       -- Whether the task succeeded (TRUE) or failed (FALSE)
                                    error_message  -- Error message if task failed, NULL otherwise
                                  FROM worker.process_tasks(priority := $1)",
            priority,
            as: {Int64, String, String, PG::Numeric, Bool, String?}

          if results.empty?
            @log.debug { "No tasks to process" }
          else
            @log.debug { "Processed #{results.size} tasks" }
            results.each do |id, command, duration, success, error|
              duration_float = duration.to_f
              if success
                @log.debug { "Task #{id} (#{command}) completed in #{duration_float.round(2)}ms" }
              else
                @log.error { "Task #{id} (#{command}) failed after #{duration_float.round(2)}ms: #{error}" }
              end
            end
          
            # Only log at INFO level if there were errors
            if results.any? { |_, _, _, success, _| !success }
              @log.info { "Processed #{results.size} tasks with errors" }
            end

            # Schedule a task cleanup if we processed tasks
            db.exec "SELECT worker.enqueue_task_cleanup()"
          end
        end
      rescue DB::ConnectionRefused | Socket::ConnectError
        @log.error { "Database connection failed while processing tasks" }
        # Don't log the full stack trace for connection issues
        sleep(5.seconds) # Wait before retrying
      rescue ex
        @log.error { "Error processing tasks: #{ex.message}" }
        @log.error { ex.backtrace.join("\n") }
      ensure
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i
        @log.debug { "Task processing completed in #{duration_ms}ms" }
      end
    end
  end
end
