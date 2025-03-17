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
#     -- Create test data and trigger worker tasks
#     INSERT INTO some_table VALUES (...);
#     -- Manually process tasks that would normally be handled by the worker
#     -- Do NOT use a transaction as worker.process_tasks() handles its own transactions
#     CALL worker.process_tasks();
#     -- Verify results
#     SELECT * FROM affected_table WHERE ...;
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
#    - Records task state and error messages
#
# Error Handling:
# - Task processing errors are recorded in the tasks table
# - Failed tasks don't block other tasks from processing
# - Detailed error messages are available for debugging
module Statbus
  class Worker
    @log : ::Log
    @config : Config
    # Increased buffer size to prevent potential deadlocks
    @timer_queue = Channel(Time).new(8)                 # Queue for scheduled tasks. We have only 1 scheduled task as of 2025-Q1
    @last_scheduled_time : Time? = nil                  # Track the last scheduled time to avoid duplicate notifications
    @last_scheduled_check = Time.utc                    # Track when we last checked for scheduled tasks
    @queue_processors = {} of String => Channel(Symbol) # Map of queue names to processor channels with large buffer
    @available_queues = [] of String                    # List of available queues
    @channel_buffer_size = 8192                         # There can be a lot of task notifications for large imports, so have a sizeable queue.
    @queue_discovery_channel = Channel(Nil).new(8)      # Channel to trigger queue discovery. We have only 3 queues as of 2025-Q1
    @shutdown = false                                   # Flag to indicate shutdown in progress
    @shutdown_complete = Channel(Bool).new(1)           # Channel to signal when shutdown is complete
    @shutdown_ack_channel = Channel(Nil).new(10)        # Channel for fibers to acknowledge shutdown
    @active_fibers = [] of Fiber                        # Track active fibers for graceful shutdown

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

      # Set up signal handlers for graceful shutdown
      setup_signal_handlers
    end

    # Set up signal handlers for graceful shutdown
    private def setup_signal_handlers
      # Handle SIGINT (Ctrl+C)
      Signal::INT.trap do
        handle_shutdown_signal("SIGINT")
      end

      # Handle SIGTERM (used by container orchestrators)
      Signal::TERM.trap do
        handle_shutdown_signal("SIGTERM")
      end

      # Handle SIGHUP (terminal disconnect)
      Signal::HUP.trap do
        handle_shutdown_signal("SIGHUP")
      end
    end

    # Common handler for shutdown signals
    private def handle_shutdown_signal(signal_name : String)
      return if @shutdown # Prevent multiple shutdown sequences

      @shutdown = true
      @log.info { "Received #{signal_name}, initiating graceful shutdown..." }

      # Start a fiber to handle the shutdown sequence
      spawn do
        # Give running fibers a chance to notice the shutdown flag
        sleep 0.5.seconds

        # Send shutdown message to timer queue
        @timer_queue.close rescue nil

        # Send shutdown message to queue discovery channel
        @queue_discovery_channel.close rescue nil

        # Send shutdown message to all queue processors and count how many were sent
        sent_count = 0
        @queue_processors.each do |queue, channel|
          begin
            channel.send(:shutdown)
            sent_count += 1
            @log.debug { "Sent shutdown message to #{queue} processor" }
          rescue ex
            @log.debug { "Failed to send shutdown message to #{queue} processor: #{ex.message}" }
          end
        end

        # Add 1 for the main fiber
        sent_count += 1
        @shutdown_ack_channel.send(nil) # Main fiber is considered already acknowledged

        # Wait for acknowledgments or timeout
        shutdown_timeout = 5.seconds
        shutdown_start = Time.monotonic
        received_count = 1 # Start with 1 for the main fiber

        loop do
          # Check if we've exceeded the timeout
          if (Time.monotonic - shutdown_start) > shutdown_timeout
            @log.warn { "Shutdown timeout reached after #{shutdown_timeout.total_seconds} seconds, forcing exit" }
            break
          end

          # Check if we've received all acknowledgments
          if received_count >= sent_count
            @log.info { "All fibers have acknowledged shutdown" }
            break
          end

          # Try to receive an acknowledgment with a short timeout
          begin
            select
            when @shutdown_ack_channel.receive
              received_count += 1
              @log.debug { "Received shutdown acknowledgment (#{received_count}/#{sent_count})" }
            when timeout(0.1.seconds)
              # Just continue the loop
            end
          rescue Channel::ClosedError
            # Channel was closed, just continue
            @log.debug { "Shutdown acknowledgment channel closed" }
            break
          end

          @log.debug { "Waiting for #{sent_count - received_count} fibers to acknowledge shutdown..." }
        end

        # Close all channels to ensure no fibers are blocked
        @queue_processors.each do |_, channel|
          channel.close rescue nil
        end
        @shutdown_ack_channel.close rescue nil

        # Signal that shutdown is complete
        @shutdown_complete.send(true) rescue nil
        @log.info { "Shutdown complete, exiting..." }
        exit(0) # Use explicit success exit code
      end

      # Wait for shutdown to complete or timeout
      begin
        select
        when @shutdown_complete.receive
          # Normal exit will happen in the shutdown fiber
        when timeout(10.seconds)
          @log.error { "Shutdown timed out after 10 seconds, forcing exit" }
          exit(1)
        end
      rescue
        # If channel is closed or other error, just exit
        exit(1)
      end
    end

    # Start the queue discovery process and initialize the first set of queues
    private def start_queue_discovery
      # Start the queue discovery processor
      fiber = spawn queue_discovery_loop
      @active_fibers << fiber

      # Trigger initial queue discovery
      @queue_discovery_channel.send(nil)
    end

    # Queue discovery loop that handles both initial and ongoing queue discovery
    private def queue_discovery_loop
      @log.info { "Starting queue discovery loop" }
      consecutive_errors = 0
      max_consecutive_errors = 5

      loop do
        break if @shutdown

        begin
          # Wait for discovery signal
          @queue_discovery_channel.receive

          DB.connect(@config.connection_string) do |db|
            # Get all available queues from the database
            current_queues = db.query_all "SELECT DISTINCT queue FROM worker.command_registry", as: String

            # Log discovered queues
            @log.info { "Found #{current_queues.size} queue(s): #{current_queues.join(", ")}" }

            # Find queues that don't have processors yet
            current_queues.each do |queue|
              unless @queue_processors.has_key?(queue)
                @log.info { "New queue detected: #{queue}" }
                # Use the standardized buffer size for consistency
                new_channel = Channel(Symbol).new(@channel_buffer_size)

                # Atomic update of data structures to prevent race conditions
                @queue_processors[queue] = new_channel
                @available_queues << queue

                # Start the processor after data structures are updated
                # The processor will automatically start processing tasks when created
                fiber = spawn process_queue_loop(queue, new_channel)
                @active_fibers << fiber
              end
            end

            # Log current queues
            @log.debug { "Current queues: #{@available_queues.join(", ")}" }
          end

          # Reset error counter after successful execution
          consecutive_errors = 0
        rescue Channel::ClosedError
          if @shutdown
            @log.info { "Queue discovery channel closed during shutdown, exiting discovery loop" }
            # Acknowledge shutdown
            @shutdown_ack_channel.send(nil) rescue nil
          else
            @log.warn { "Queue discovery channel closed unexpectedly, shutting down discovery loop" }
          end
          break
        rescue ex
          consecutive_errors += 1
          @log.error { "Error in queue discovery: #{ex.message}" }
          @log.error { ex.backtrace.join("\n") }

          # Implement circuit breaker pattern for persistent errors
          if consecutive_errors >= max_consecutive_errors
            @log.error { "Too many consecutive errors (#{consecutive_errors}), pausing discovery loop for recovery" }
            sleep(60.seconds)      # Longer pause to allow system to recover
            consecutive_errors = 0 # Reset after recovery period
          else
            sleep(10.seconds) # Wait before retrying
          end
        end
      end

      # Acknowledge shutdown before exiting
      if @shutdown
        @shutdown_ack_channel.send(nil) rescue nil
      end
    end

    def run
      # Wait for worker schema to be ready before starting processing
      wait_for_worker_schema

      # Start queue discovery process (replaces initialize_queue_processors and start_queue_processors)
      start_queue_discovery

      # Start timer checking fiber
      fiber = spawn check_scheduled_tasks_loop
      @active_fibers << fiber

      # Each queue processor will automatically start processing when created

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
            # We already checked for worker schema in wait_for_worker_schema, no need to check again
          end

          # Listen for notifications in a background thread
          connection = PG.connect_listen(@config.connection_string, channels: ["worker_tasks", "worker_queue_change"], blocking: true) do |notification|
            if notification.channel == "worker_tasks"
              # Get the queue from the notification payload
              queue_name = notification.payload.presence

              # If a specific queue was mentioned in the notification
              if queue_name && @queue_processors.has_key?(queue_name)
                @log.debug { "Received notification for specific queue: #{queue_name}" }
                # Only notify the specific queue mentioned in the notification
                @queue_processors[queue_name].send(:process)
              else
                # Only if payload is empty or queue doesn't exist, notify all processors
                @log.debug { "Received notification without specific queue, notifying all queues" }
                @queue_processors.each do |queue, channel|
                  channel.send(:process)
                end
              end
            elsif notification.channel == "worker_queue_change"
              # When queue change notification received, trigger queue discovery
              @log.info { "Queue change detected, triggering queue discovery..." }
              @queue_discovery_channel.send(nil)
            end
          end

          # Log successful connection
          @log.debug { "Connected to database at #{@config.postgres_host}:#{@config.postgres_port}" }

          # Reset retry parameters after successful connection
          retry_count = 0
          retry_delay = 1.seconds

          # The connection is already in listening mode and will block in the background
          # Just wait indefinitely until an exception occurs or the program is terminated
          until @shutdown
            sleep(1.seconds)
          end

          # If we're shutting down, close the connection gracefully
          if @shutdown
            @log.info { "Shutting down database connection..." }
            connection.close rescue nil
          end

          # If we get here, the connection was closed normally
          @log.info { "Database connection closed, reconnecting..." }
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

    # Helper method to notify appropriate processors
    private def notify_processors(queue : String?)
      if queue && @queue_processors.has_key?(queue)
        @log.debug { "Notifying specific queue processor: #{queue}" }
        @queue_processors[queue].send(:process)
      else
        # Notify all queue processors if queue is unknown
        @log.debug { "Notifying all queue processors" }
        @queue_processors.each do |q, channel|
          channel.send(:process)
        end
      end
    end

    # Continuously check for scheduled tasks
    private def check_scheduled_tasks_loop
      consecutive_errors = 0
      max_consecutive_errors = 5
      last_processed_time : Time? = nil

      loop do
        break if @shutdown

        begin
          # Find the next scheduled task
          next_scheduled, queue = find_next_scheduled_task

          if next_scheduled.nil?
            # No scheduled tasks, wait for a while but check for shutdown frequently
            wait_with_shutdown_check(60.seconds)
            next
          end

          # Skip if we've already processed this exact scheduled time
          if last_processed_time == next_scheduled
            wait_with_shutdown_check(60.seconds) # Wait before checking again
            next
          end

          # Calculate time until next task
          now = Time.utc
          time_until_next = next_scheduled - now

          if time_until_next.total_seconds <= 0
            # Task is due now or overdue
            @log.debug { "Task overdue for queue #{queue || "unknown"}, processing now" }
            notify_processors(queue)
            last_processed_time = next_scheduled # Remember we processed this time
            wait_with_shutdown_check(1.seconds)  # Prevent tight loop
            next
          end

          # Wait for the scheduled time or until interrupted
          @log.debug { "Next scheduled task at #{next_scheduled} for queue #{queue || "unknown"}, waiting #{time_until_next.total_seconds.round(2)} seconds" }

          # Use a timeout to wait for either a new scheduled task or the current one to be due
          begin
            select
            when new_time = @timer_queue.receive
              # A new scheduled task was found with an earlier time, restart the loop
              if new_time < next_scheduled
                @log.debug { "Timer interrupted by earlier scheduled task: #{new_time}" }
                # Don't set last_processed_time here as we're just restarting the loop
              else
                @log.debug { "Received notification for task at #{new_time}, but keeping current schedule for #{next_scheduled}" }
              end
            when timeout(time_until_next)
              # Time to process the scheduled task
              @log.debug { "Timer expired, processing scheduled tasks for queue #{queue || "unknown"}" }
              notify_processors(queue)
              last_processed_time = next_scheduled # Remember we processed this time
            end
          rescue ex : Channel::ClosedError
            # Handle channel closed during select
            raise ex
          end

          # Reset error counter after successful execution
          consecutive_errors = 0
        rescue Channel::ClosedError
          if @shutdown
            @log.info { "Timer channel closed during shutdown, exiting timer loop" }
            # Acknowledge shutdown
            @shutdown_ack_channel.send(nil) rescue nil
          else
            @log.warn { "Timer channel closed unexpectedly, shutting down timer loop" }
          end
          break
        rescue ex
          consecutive_errors += 1
          @log.error { "Error in scheduled task checker: #{ex.message}" }
          @log.error { ex.backtrace.join("\n") }

          # Implement circuit breaker pattern for persistent errors
          if consecutive_errors >= max_consecutive_errors
            @log.error { "Too many consecutive errors (#{consecutive_errors}), pausing timer loop for recovery" }
            wait_with_shutdown_check(60.seconds) # Longer pause to allow system to recover
            consecutive_errors = 0               # Reset after recovery period
          else
            wait_with_shutdown_check(10.seconds) # Wait a bit before retrying
          end
        end
      end

      # Acknowledge shutdown before exiting
      if @shutdown
        @shutdown_ack_channel.send(nil) rescue nil
      end
    end

    # Helper method to wait while checking for shutdown
    private def wait_with_shutdown_check(duration : Time::Span)
      start_time = Time.monotonic
      while (Time.monotonic - start_time) < duration
        return if @shutdown
        sleep(0.1.seconds) # Check for shutdown frequently
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
                               WHERE t.state = 'pending'
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

      # Process tasks immediately upon starting
      @log.debug { "Initial processing for queue: #{queue}" }
      process_tasks(queue)

      # Check for new scheduled tasks after initial processing, but only once at startup
      check_for_new_scheduled_tasks

      loop do
        break if @shutdown

        begin
          command = channel.receive

          case command
          when :process
            @log.debug { "Processing tasks for queue: #{queue}" }
            process_tasks(queue)

            # Only check for scheduled tasks when processing due to a notification
            # This prevents the feedback loop where every process triggers more processes
            if queue == "maintenance" # Only maintenance queue handles scheduled tasks
              check_for_new_scheduled_tasks
            end
          when :shutdown
            @log.info { "Received shutdown command for #{queue} process loop" }
            break
          end
        rescue Channel::ClosedError
          if @shutdown
            @log.info { "Queue channel closed during shutdown, exiting #{queue} process loop" }
          else
            @log.warn { "Queue channel closed unexpectedly, shutting down #{queue} process loop" }
          end
          break
        rescue ex
          @log.error { "Error in #{queue} process loop: #{ex.message}" }
          @log.error { ex.backtrace.join("\n") }
          wait_with_shutdown_check(1.seconds) # Prevent tight loop on error while checking for shutdown
        end
      end

      # Acknowledge shutdown before exiting
      if @shutdown
        @log.debug { "#{queue} processor acknowledging shutdown" }
        @shutdown_ack_channel.send(nil) rescue nil
      end
    end

    # This method has been replaced by the queue_discovery_loop

    # Track when we last checked for scheduled tasks to avoid redundant checks
    @last_scheduled_check = Time.utc

    # Check if any new scheduled tasks have been added
    private def check_for_new_scheduled_tasks
      # Only check for new scheduled tasks at most once per minute
      # This prevents excessive database queries
      now = Time.utc
      if (now - @last_scheduled_check).total_seconds < 60
        return
      end

      @last_scheduled_check = now
      next_scheduled, queue = find_next_scheduled_task

      # Only notify if we have a scheduled task and it's different from the last one we saw
      if next_scheduled && next_scheduled != @last_scheduled_time
        @log.debug { "New scheduled time detected: #{next_scheduled} (previous: #{@last_scheduled_time || "none"})" }
        @last_scheduled_time = next_scheduled

        # Notify the timer checker about the new task
        @timer_queue.send(next_scheduled)

        # We don't need to notify processors here - the timer will do that when the time comes
        # This prevents the feedback loop of continuous processing
      end
    end

    # Process pending tasks for a specific queue
    private def process_tasks(queue : String)
      start_time = Time.monotonic
      consecutive_errors = 0
      max_consecutive_errors = 3

      begin
        # Use a connection pool or reuse connection if possible
        DB.connect(@config.connection_string) do |db|
          # Call worker.process_tasks() procedure
          # The p_queue parameter ensures we only process tasks for this specific queue
          # Note: worker.process_tasks() handles its own transactions internally
          @log.debug { "Executing worker.process_tasks for queue: #{queue}" }

          # First execute the CALL statement
          db.exec "CALL worker.process_tasks(p_queue => $1, p_batch_size => $2)", queue, 10

          # Then execute the SELECT statement to get results
          results = db.query_all "SELECT
                                    t.id AS task_id, -- The task ID
                                    t.command,       -- The command that was executed
                                    cr.queue,        -- The task queue
                                    duration_ms,     -- Duration in ms from the database
                                    state = 'completed'::worker.task_state AS success, -- Whether task succeeded
                                    error_message    -- Error message if task failed, NULL otherwise
                                  FROM worker.tasks t
                                  JOIN worker.command_registry cr ON t.command = cr.command
                                  WHERE processed_at IS NOT NULL
                                  AND age(processed_at) < interval '10 seconds'
                                  AND (cr.queue = $1 OR $1 IS NULL)
                                  ORDER BY processed_at DESC",
            queue,
            as: {Int64, String, String, PG::Numeric, Bool, String?}

          if results.empty?
            @log.debug { "No tasks to process for queue: #{queue}" }
          else
            @log.debug { "Processed #{results.size} tasks for queue: #{queue}" }
            results.each do |id, command, task_queue, duration, success, error|
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
          end

          # Reset error counter after successful execution
          consecutive_errors = 0
        end
      rescue DB::ConnectionRefused | Socket::ConnectError
        consecutive_errors += 1
        @log.error { "Database connection failed while processing tasks for queue: #{queue}" }

        # Implement circuit breaker pattern
        if consecutive_errors >= max_consecutive_errors
          @log.error { "Too many consecutive connection errors (#{consecutive_errors}), pausing queue processor" }
          sleep(30.seconds)      # Longer pause to allow database to recover
          consecutive_errors = 0 # Reset after recovery period
        else
          sleep(5.seconds) # Wait before retrying
        end
      rescue ex
        consecutive_errors += 1
        @log.error { "Error processing tasks for queue #{queue}: #{ex.message}" }
        @log.error { ex.backtrace.join("\n") }

        # Implement circuit breaker pattern
        if consecutive_errors >= max_consecutive_errors
          @log.error { "Too many consecutive errors (#{consecutive_errors}), pausing queue processor" }
          sleep(30.seconds)      # Longer pause to allow system to recover
          consecutive_errors = 0 # Reset after recovery period
        else
          sleep(5.seconds) # Wait before retrying
        end
      ensure
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i
        @log.debug { "Task processing for queue #{queue} completed in #{duration_ms}ms" }
      end
    end
  end
end
