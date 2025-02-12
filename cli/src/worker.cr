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
              when "deleted_row"
                CommandDeletedRow.new(
                  table_name: payload["table_name"].as_s,
                  id: payload["id"].as_i64,
                  establishment_id: payload["establishment_id"]?.try(&.as_i64?),
                  legal_unit_id: payload["legal_unit_id"]?.try(&.as_i64?),
                  enterprise_id: payload["enterprise_id"]?.try(&.as_i64?),
                  valid_after: payload["valid_after"]?.try(&.as_s?).try { |s| Time.parse(s, "%F", Time::Location::UTC) },
                  valid_from: payload["valid_from"]?.try(&.as_s?).try { |s| Time.parse(s, "%F", Time::Location::UTC) },
                  valid_to: payload["valid_to"]?.try(&.as_s?).try { |s| Time.parse(s, "%F", Time::Location::UTC) }
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

    private def process_command(cmd)
      @log.info { "Processing #{cmd.inspect}" }
      start_time = Time.monotonic
      begin
        DB.connect(@config.connection_string) do |db|
          case cmd
          in CommandPing
            db.exec "SELECT worker.pong($1);", cmd.ident
          in CommandRefreshMaterializedViews
            db.exec "SELECT public.statistical_unit_refresh_now();"
          in CommandUpdateStatisticalUnit
            command_update_statistical_unit(db, cmd)
          in CommandCheckTable
            command_check_table(db, cmd)
          in CommandDeletedRow
            command_deleted_row(db, cmd)
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

      # Create unlogged pong table for ping responses
      db.exec <<-SQL
        CREATE UNLOGGED TABLE IF NOT EXISTS worker.pong (
          ident bigint PRIMARY KEY,
          expires_at timestamp with time zone NOT NULL DEFAULT (now() + interval '10 minutes')
        );
      SQL

      # Create trigger to clean expired pong entries
      db.exec <<-SQL
        DROP TRIGGER IF EXISTS delete_expired_pongs_trigger ON worker.pong;
      SQL

      db.exec <<-SQL
        DROP FUNCTION IF EXISTS worker.delete_expired_pongs() CASCADE;
      SQL

      db.exec <<-SQL
        CREATE FUNCTION worker.delete_expired_pongs()
        RETURNS trigger
        LANGUAGE plpgsql
        AS $function$
        BEGIN
          DELETE FROM worker.pong WHERE expires_at < now();
          RETURN NULL;
        END;
        $function$;
      SQL

      db.exec <<-SQL
        CREATE TRIGGER delete_expired_pongs_trigger
        AFTER INSERT ON worker.pong
        FOR EACH STATEMENT
        EXECUTE FUNCTION worker.delete_expired_pongs();
      SQL

      # Create function to handle ping responses
      db.exec <<-SQL
        DROP FUNCTION IF EXISTS worker.pong(bigint);
      SQL
      db.exec <<-SQL
        CREATE FUNCTION worker.pong(p_ident bigint)
        RETURNS void
        LANGUAGE plpgsql
        AS $function$
        BEGIN
          -- Insert into pong table
          INSERT INTO worker.pong (ident)
          VALUES (p_ident);

          -- Send notification
          PERFORM pg_notify('pong', p_ident::text);
        END;
        $function$;
      SQL

      # Create ping function that notifies worker and waits for response
      db.exec <<-SQL
        DROP FUNCTION IF EXISTS worker.ping(bigint, interval);
      SQL
      db.exec <<-SQL
        CREATE FUNCTION worker.ping(
          p_ident bigint,
          p_timeout interval DEFAULT interval '60 seconds'
        ) RETURNS bigint
        LANGUAGE plpgsql
        AS $function$
        DECLARE
          v_start timestamp with time zone;
          v_found_ident bigint;
        BEGIN
          -- Send ping notification
          PERFORM pg_notify('worker', json_build_object(
            'command', 'ping',
            'ident', p_ident
          )::text);

          v_start := clock_timestamp();
          v_found_ident := NULL;

          -- Loop until response found or timeout
          WHILE clock_timestamp() < v_start + p_timeout AND v_found_ident IS NULL LOOP
            -- Check for response
            DELETE FROM worker.pong
            WHERE ident = p_ident
            RETURNING ident INTO v_found_ident;

            IF v_found_ident IS NULL THEN
              -- Wait a bit before checking again
              PERFORM pg_sleep(0.1);
            END IF;
          END LOOP;

          RETURN COALESCE(v_found_ident, 0); -- Return 0 if no response found
        END;
        $function$;
      SQL

      # Create trigger functions for changes and deletes
      db.exec <<-SQL
        DROP FUNCTION IF EXISTS worker.notify_worker_about_changes() CASCADE;
      SQL
      db.exec <<-SQL
        DROP FUNCTION IF EXISTS worker.notify_worker_about_deletes() CASCADE;
      SQL

      db.exec <<-SQL
        CREATE FUNCTION worker.notify_worker_about_changes()
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

      db.exec <<-SQL
        CREATE FUNCTION worker.notify_worker_about_deletes()
        RETURNS trigger
        LANGUAGE plpgsql
        AS $function$
        DECLARE
          payload jsonb;
          establishment_id_value int;
          legal_unit_id_value int;
          enterprise_id_value int;
          valid_after_value date;
          valid_from_value date;
          valid_to_value date;
        BEGIN
          -- Set values based on table name
          CASE TG_TABLE_NAME
            WHEN 'establishment' THEN
              establishment_id_value := OLD.id;
              legal_unit_id_value := OLD.legal_unit_id;
              enterprise_id_value := OLD.enterprise_id;
              valid_after_value := OLD.valid_after;
              valid_from_value := OLD.valid_from;
              valid_to_value := OLD.valid_to;
            WHEN 'legal_unit' THEN
              establishment_id_value := NULL;
              legal_unit_id_value := OLD.id;
              enterprise_id_value := OLD.enterprise_id;
              valid_after_value := OLD.valid_after;
              valid_from_value := OLD.valid_from;
              valid_to_value := OLD.valid_to;
            WHEN 'enterprise' THEN
              establishment_id_value := NULL;
              legal_unit_id_value := NULL;
              enterprise_id_value := OLD.id;
              valid_after_value := NULL;
              valid_from_value := NULL;
              valid_to_value := NULL;
            WHEN 'activity' THEN
              establishment_id_value := OLD.establishment_id;
              legal_unit_id_value := OLD.legal_unit_id;
              enterprise_id_value := NULL;
              valid_after_value := OLD.valid_after;
              valid_from_value := OLD.valid_from;
              valid_to_value := OLD.valid_to;
            WHEN 'location' THEN
              establishment_id_value := OLD.establishment_id;
              legal_unit_id_value := OLD.legal_unit_id;
              enterprise_id_value := NULL;
              valid_after_value := OLD.valid_after;
              valid_from_value := OLD.valid_from;
              valid_to_value := OLD.valid_to;
            WHEN 'contact' THEN
              establishment_id_value := OLD.establishment_id;
              legal_unit_id_value := OLD.legal_unit_id;
              enterprise_id_value := NULL;
              valid_after_value := OLD.valid_after;
              valid_from_value := OLD.valid_from;
              valid_to_value := OLD.valid_to;
            WHEN 'stat_for_unit' THEN
              establishment_id_value := OLD.establishment_id;
              legal_unit_id_value := OLD.legal_unit_id;
              enterprise_id_value := NULL;
              valid_after_value := OLD.valid_after;
              valid_from_value := OLD.valid_from;
              valid_to_value := OLD.valid_to;
          END CASE;

          -- Build the payload
          payload := json_build_object(
            'command', 'deleted_row',
            'table_name', TG_TABLE_NAME,
            'id', OLD.id,
            'establishment_id', establishment_id_value,
            'legal_unit_id', legal_unit_id_value,
            'enterprise_id', enterprise_id_value,
            'valid_after', valid_after_value,
            'valid_from', valid_from_value,
            'valid_to', valid_to_value
          );

          -- Send notification
          PERFORM pg_notify('worker', payload::text);
          
          RETURN OLD;
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
              'enterprise',
              'legal_unit',
              'establishment',
              'activity',
              'location',
              'contact',
              'stat_for_unit'
            ])
          LOOP
            -- Create delete trigger
            IF NOT EXISTS (
              SELECT 1 FROM pg_trigger
              WHERE tgname = table_name || '_deletes_trigger'
              AND tgrelid = ('public.' || table_name)::regclass
            ) THEN
              EXECUTE format(
                'CREATE TRIGGER %I
                BEFORE DELETE ON public.%I
                FOR EACH ROW
                EXECUTE FUNCTION worker.notify_worker_about_deletes()',
                table_name || '_deletes_trigger',
                table_name
              );
            END IF;

            -- Create changes trigger for inserts and updates
            IF NOT EXISTS (
              SELECT 1 FROM pg_trigger
              WHERE tgname = table_name || '_changes_trigger'
              AND tgrelid = ('public.' || table_name)::regclass
            ) THEN
              EXECUTE format(
                'CREATE TRIGGER %I
                AFTER INSERT OR UPDATE ON public.%I
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
                        when "establishment"
                          <<-SQL
                          , id AS establishment_id
                          , legal_unit_id
                          , enterprise_id
                          SQL
                        when "legal_unit"
                          <<-SQL
                          , NULL::INT AS establishment_id
                          , id AS legal_unit_id
                          , enterprise_id
                          SQL
                        when "enterprise"
                          <<-SQL
                          , NULL::INT AS establishment_id
                          , NULL::INT AS legal_unit_id
                          , id AS enterprise_id
                          SQL
                        when "activity", "location", "contact", "stat_for_unit"
                          # Each of the tables may have establiishment_id and legal_unit_id, but not enterprise_id
                          <<-SQL
                          , establishment_id
                          , legal_unit_id
                          , NULL::INT AS enterprise_id
                          SQL
                        else
                          raise "Unknown table: #{cmd.table_name}"
                        end
      # Find changed rows since last processing
      valid_columns = case cmd.table_name
                      when "enterprise"
                        <<-SQL
                          , NULL::DATE AS valid_after
                          , NULL::DATE AS valid_from
                          , NULL::DATE AS valid_to
                          SQL
                      when "establishment", "legal_unit", "activity", "location", "contact", "stat_for_unit"
                        <<-SQL
                          , NULLIF(valid_after, '-infinity'::DATE) AS valid_after
                          , NULLIF(valid_from, '-infinity'::DATE) AS valid_from
                          , NULLIF(valid_to, 'infinity'::DATE) AS valid_to
                          SQL
                      else
                        raise "Unknown table: #{cmd.table_name}"
                      end

      changed_rows = db.query_all <<-SQL, cmd.transaction_id, as: ChangedRow.types
        SELECT id
             #{unit_id_columns}
             #{valid_columns}
        FROM #{cmd.table_name}
        WHERE age($1::xid) >= age(xmin)
        ORDER BY id;
      SQL

      # Collect and track IDs with their validity periods
      collection = UnitCollection.new

      changed_rows.each do |row|
        @log.info { "Analyzing changed #{cmd.table_name} row #{row.inspect}" }

        # Update collection with the changed row
        collection = update_unit_collection(collection, row)
      end

      @log.debug { "Processing collection: #{collection.inspect}" }

      # Process collected IDs if any exist
      unless collection.establishment_ids.empty? && collection.legal_unit_ids.empty? && collection.enterprise_ids.empty?
        # Remove existing entries for these IDs in the relevant time range.
        db.transaction do |tx|
          # Delete all affected entries in one operation
          delete_from_statistical_unit(tx, collection)

          # Insert all new entries in one operation
          insert_into_statistical_unit(tx, collection)
        end
      end

      # Update last processed transaction
      db.exec <<-SQL, cmd.table_name, current_txid
        INSERT INTO worker.last_processed (table_name, transaction_id)
        VALUES ($1, $2)
        ON CONFLICT (table_name)
        DO UPDATE SET transaction_id = EXCLUDED.transaction_id;
      SQL
    end

    private def command_deleted_row(db, cmd : CommandDeletedRow)
      # Create a collection from the deleted row
      collection = UnitCollection.new
      collection = update_unit_collection(collection, {
        id:               cmd.id.to_i32,
        establishment_id: cmd.establishment_id.try(&.to_i32),
        legal_unit_id:    cmd.legal_unit_id.try(&.to_i32),
        enterprise_id:    cmd.enterprise_id.try(&.to_i32),
        valid_after:      cmd.valid_after,
        valid_from:       cmd.valid_from,
        valid_to:         cmd.valid_to,
      })

      # Remove existing entries for these IDs in the relevant time range
      db.transaction do |tx|
        delete_from_statistical_unit(tx, collection)
      end
    end

    private def delete_from_statistical_unit(tx : DB::Transaction, collection : UnitCollection)
      tx.connection.exec <<-SQL, collection.establishment_ids.to_a, collection.legal_unit_ids.to_a, collection.enterprise_ids.to_a, collection.valid_after || "-infinity", collection.valid_to || "infinity"
        DELETE FROM public.statistical_unit
        WHERE (
          -- Direct matches on unit_id for any type
          (unit_type = 'establishment' AND unit_id = ANY($1::int[])) OR
          (unit_type = 'legal_unit' AND unit_id = ANY($2::int[])) OR
          (unit_type = 'enterprise' AND unit_id = ANY($3::int[])) OR
          -- Subset matches of array columns of dependencies
          establishment_ids <@ $1::int[] OR
          legal_unit_ids <@ $2::int[] OR
          enterprise_ids <@ $3::int[]
        )
        AND daterange(valid_after, valid_to, '(]') &&
            daterange($4::DATE, $5::DATE, '(]');
      SQL
    end

    private def insert_into_statistical_unit(tx : DB::Transaction, collection : UnitCollection)
      tx.connection.exec <<-SQL, collection.establishment_ids.to_a, collection.legal_unit_ids.to_a, collection.enterprise_ids.to_a, collection.valid_after || "-infinity", collection.valid_to || "infinity"
        INSERT INTO public.statistical_unit
        SELECT * FROM public.statistical_unit_def
        WHERE (
          -- Direct matches on unit_id for any type
          (unit_type = 'establishment' AND unit_id = ANY($1::int[])) OR
          (unit_type = 'legal_unit' AND unit_id = ANY($2::int[])) OR
          (unit_type = 'enterprise' AND unit_id = ANY($3::int[])) OR
          -- Subset matches of array columns of dependencies
          establishment_ids <@ $1::int[] OR
          legal_unit_ids <@ $2::int[] OR
          enterprise_ids <@ $3::int[]
        )
        AND daterange(valid_after, valid_to, '(]') &&
            daterange($4::DATE, $5::DATE, '(]');
      SQL
    end

    private def command_update_statistical_unit(db, cmd : CommandUpdateStatisticalUnit)
      db.exec "SELECT public.statistical_unit_refresh_now();"
    end

    private def update_unit_collection(collection : UnitCollection, row : ChangedRow) : UnitCollection
      new_valid_after = combine_times(row[:valid_after], collection.valid_after, :min)
      new_valid_to = combine_times(row[:valid_to], collection.valid_to, :max)

      # Create new sets with added IDs if present
      establishment_ids = collection.establishment_ids
      if establishment_id = row[:establishment_id]
        establishment_ids = establishment_ids.dup << establishment_id
      end

      legal_unit_ids = collection.legal_unit_ids
      if legal_unit_id = row[:legal_unit_id]
        legal_unit_ids = legal_unit_ids.dup << legal_unit_id
      end

      enterprise_ids = collection.enterprise_ids
      if enterprise_id = row[:enterprise_id]
        enterprise_ids = enterprise_ids.dup << enterprise_id
      end

      collection.copy_with(
        establishment_ids: establishment_ids,
        legal_unit_ids: legal_unit_ids,
        enterprise_ids: enterprise_ids,
        valid_after: new_valid_after,
        valid_to: new_valid_to
      )
    end

    private def combine_times(row_time : Time?, current_time : Time?, choose : Symbol) : Time?
      if row_time.nil? && current_time.nil?
        nil
      elsif row_time.nil?
        current_time
      elsif current_time.nil?
        row_time
      else
        if choose == :max
          row_time > current_time ? row_time : current_time
        else
          row_time < current_time ? row_time : current_time
        end
      end
    end

    alias ChangedRow = {id: Int32, establishment_id: Int32?, legal_unit_id: Int32?, enterprise_id: Int32?, valid_after: Time?, valid_from: Time?, valid_to: Time?}

    record UnitCollection,
      establishment_ids : Set(Int32) = Set(Int32).new,
      legal_unit_ids : Set(Int32) = Set(Int32).new,
      enterprise_ids : Set(Int32) = Set(Int32).new,
      valid_after : Time? = nil, # nil = -infinity
      valid_to : Time? = nil     # nil = infinity

    record CommandPing, ident : Int64
    record CommandRefreshMaterializedViews
    record CommandUpdateStatisticalUnit, unit_type : String, unit_id : Int64
    record CommandDeletedRow,
      table_name : String,
      id : Int64,
      establishment_id : Int64?,
      legal_unit_id : Int64?,
      enterprise_id : Int64?,
      valid_after : Time?,
      valid_from : Time?,
      valid_to : Time?
    record CommandCheckTable, table_name : String, transaction_id : Int64
    alias Command = CommandPing |
                    CommandRefreshMaterializedViews |
                    CommandUpdateStatisticalUnit |
                    CommandCheckTable |
                    CommandDeletedRow
  end
end
