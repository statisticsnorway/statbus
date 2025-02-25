require "json"
require "log"
require "pg"
require "./config"

# Worker Architecture
#
# The Worker system can operate in two modes:
#
# 1. Background Mode (Default):
#    - Tasks are managed in the worker.tasks table
#    - This Crystal worker process listens for notifications
#    - Suitable for production deployment
#    - Asynchronous processing outside transaction boundaries
#    - Set with: SELECT worker.mode('background');
#
# 2. Manual Mode:
#    - Tasks are stored in the worker.tasks table
#    - No Crystal worker process needed
#    - Suitable for testing since tasks can be processed manually
#    - Changes can be rolled back with test transaction ABORT
#    - Set with: SELECT worker.mode('manual');
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
    @command_queue = Channel(Symbol).new(10) # Bounded queue to prevent memory issues
    @timer_queue = Channel(Time).new(10)     # Queue for scheduled tasks

    def initialize(config)
      @config = config
      @log = ::Log.for("worker")
      Log.setup_from_env
    end

    def run
      Signal::INT.trap do
        @log.info { "Received CTRL-C, shutting down..." }
        exit
      end

      # Start processing fiber
      spawn process_commands_loop

      # Start timer checking fiber
      spawn check_scheduled_tasks_loop

      # Queue initial processing on startup
      @command_queue.send(:process)

      # Listen for notifications in a background thread
      connection = PG.connect_listen(@config.connection_string, channels: ["worker_tasks"], blocking: true) do |notification|
        # When notification received, queue a processing command
        @command_queue.send(:process)
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
                @command_queue.send(:process)
              end
            else
              # Task is due now or overdue
              @command_queue.send(:process)
              sleep(1.seconds) # Prevent tight loop
            end
          else
            # No scheduled tasks, wait for a while
            sleep(60.seconds) # Check every minute
          end
        rescue ex
          @log.error { "Error in scheduled task checker: #{ex.message}" }
          sleep(10.seconds) # Wait a bit before retrying
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
    rescue ex
      @log.error { "Error finding next scheduled task: #{ex.message}" }
      return nil
    end

    # Main processing loop that runs in a separate fiber
    private def process_commands_loop
      loop do
        command = @command_queue.receive

        case command
        when :process
          process_tasks
        end

        # Check for new scheduled tasks after processing
        check_for_new_scheduled_tasks
      end
    end

    # Check if any new scheduled tasks have been added
    private def check_for_new_scheduled_tasks
      next_scheduled = find_next_scheduled_task
      if next_scheduled
        # Notify the timer checker about the new task
        @timer_queue.send(next_scheduled)
      end
    end

    # Process pending tasks
    private def process_tasks
      start_time = Time.monotonic
      begin
        DB.connect(@config.connection_string) do |db|
          # Query worker.process_tasks() with named columns for better documentation
          results = db.query_all "SELECT
                                    id,            -- The task ID
                                    command,       -- The command that was executed
                                    duration_ms,   -- How long the task took to process in milliseconds
                                    success,       -- Whether the task succeeded (TRUE) or failed (FALSE)
                                    error_message  -- Error message if task failed, NULL otherwise
                                  FROM worker.process_tasks(50, 5000)",
            as: {Int64, String, Float64, Bool, String?}

          if results.empty?
            @log.debug { "No tasks to process" }
          else
            @log.info { "Processed #{results.size} tasks" }
            results.each do |id, command, duration, success, error|
              if success
                @log.debug { "Task #{id} (#{command}) completed in #{duration.round(2)}ms" }
              else
                @log.error { "Task #{id} (#{command}) failed after #{duration.round(2)}ms: #{error}" }
              end
            end

            # Schedule a task cleanup if we processed tasks
            db.exec "SELECT worker.enqueue_task_cleanup()"
          end
        end
      rescue ex
        @log.error { "Error processing tasks: #{ex.message}" }
      ensure
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i
        @log.debug { "Task processing completed in #{duration_ms}ms" }
      end
    end
  end
end
