require "./config"

module Statbus
  class Migrate
    enum Mode
      Up
      Down
      New
      Redo
      Convert
    end

    property mode : Mode | Nil = nil
    property migrate_all = true
    property migrate_to : Int64? = nil
    property migration_major_description : String | Nil = nil
    property migration_minor_description : String | Nil = nil
    property migration_extension : String | Nil = nil
    property convert_start_date = Time.utc(2024, 1, 1)
    property convert_spacing = 1.day
    property config : Config

    def initialize(config)
      @config = config
    end

    def run(option_parser : OptionParser)
      case @mode
      in Mode::Up
        migrate_up
      in Mode::Down
        migrate_down
      in Mode::New
        create_new_migration
      in Mode::Redo
        @migrate_all = false # Ensure we only do one migration
        migrate_down
        migrate_up
      in Migrate::Mode::Convert
        convert_migrations
      in nil
        puts option_parser
        exit(1)
      end
    end

    def migrate_up
      Dir.cd(@config.project_directory) do
        migration_paths = [Path["migrations/**/*.up.sql"], Path["migrations/**/*.up.psql"]]
        migration_filenames = Dir.glob(migration_paths)

        # Parse and sort migrations by version number
        migrations = migration_filenames.map { |path| MigrationFile.parse(Path[path]) }
        sorted_migrations = migrations.sort_by { |m| m.version }

        if sorted_migrations.empty?
          puts "No up migrations found in #{migration_paths}"
          return
        end

        DB.connect(config.connection_string) do |db|
          ensure_migration_table(db)

          applied_count = 0
          sorted_migrations.each do |migration|
            # Stop if we've hit our target conditions
            migrate_to = @migrate_to # Thread safe access to variable for null handling

            if (!@migrate_all && applied_count > 0) ||
               (migrate_to && migration.version > migrate_to)
              break
            end

            if apply_migration(db, migration)
              applied_count += 1
            end
          end

          # Notify PostgREST to reload config and schema after all migrations
          if applied_count > 0
            db.transaction do |tx|
              puts "Notifying PostgREST to reload with changes." if @config.verbose
              tx.connection.exec("NOTIFY pgrst, 'reload config'")
              tx.connection.exec("NOTIFY pgrst, 'reload schema'")
            end
          end
        end
      end
    end

    def migrate_down
      Dir.cd(@config.project_directory) do
        DB.connect(config.connection_string) do |db|
          # Check if migrations table exists
          table_exists = db.query_one?("SELECT EXISTS (
        SELECT FROM pg_tables
        WHERE schemaname = 'db'
        AND tablename = 'migration'
      )", as: Bool)

          if !table_exists
            puts "No migrations to roll back - migration table doesn't exist"
            return
          end

          migrations_to_rollback = if @migrate_all || @migrate_to
                                     get_migrations_to_rollback(db, @migrate_to)
                                   else
                                     # Get just the last migration
                                     [db.query_one?(
                                       "SELECT version::TEXT FROM db.migration ORDER BY version DESC LIMIT 1",
                                       as: {version: String}
                                     )].compact
                                   end

          applied_count = 0
          migrations_to_rollback.each do |migration|
            version = migration[:version]
            if down_path = find_down_migration(version)
              execute_down_migration(db, down_path, version)
              applied_count += 1
            else
              raise "Missing down migration for version #{version}"
            end
          end

          cleanup_migration_schema(db) if @migrate_all || (!@migrate_all && applied_count == 0)

          # Only notify if any migrations were actually rolled back
          if applied_count > 0
            db.transaction do |tx|
              puts "Notifying PostgREST to reload with changes." if @config.verbose
              tx.connection.exec("NOTIFY pgrst, 'reload config'")
              tx.connection.exec("NOTIFY pgrst, 'reload schema'")
            end
          end
        end
      end
    end

    private def format_migration_timestamp(time : Time) : String
      time.to_s("%Y%m%d%H%M%S")
    end

    def convert_migrations
      Dir.cd(@config.project_directory) do
        # Get all existing migrations
        migration_paths = Dir.glob("migrations/*.up.sql")

        # Sort them by current version to maintain order
        migrations = migration_paths.map { |path|
          path = Path[path]
          if match = path.basename.match(/^(\d{4}_\d{3})_([^.]+)\.up\.sql$/)
            {
              old_version: match[1],
              description: match[2],
              path:        path,
            }
          end
        }.compact.sort_by { |m| m[:old_version] }

        # Rename each file with new timestamp-based version
        migrations.each_with_index do |migration, i|
          new_timestamp = @convert_start_date + (@convert_spacing * (i + 1))
          new_name = "#{format_migration_timestamp(new_timestamp)}_#{migration[:description]}"

          # Rename up file
          up_old_path = migration[:path]
          up_new_path = up_old_path.parent.join("#{new_name}.up.sql")
          File.rename(up_old_path.to_s, up_new_path.to_s)

          # Rename corresponding down file
          down_old_path = up_old_path.to_s.sub(".up.sql", ".down.sql")
          down_new_path = up_new_path.to_s.sub(".up.sql", ".down.sql")
          File.rename(down_old_path, down_new_path) if File.exists?(down_old_path)

          puts "Renamed: #{up_old_path.basename} -> #{up_new_path.basename}"
        end
      end
    end

    def create_new_migration
      Dir.cd(@config.project_directory) do
        if @migration_minor_description.nil?
          STDERR.puts "Missing required description for migration. Use:"
          STDERR.puts "  -d/--description to specify the migration description"
          exit(1)
        end

        # Generate timestamp version
        timestamp = format_migration_timestamp(Time.utc)

        # Create safe description
        safe_desc = @migration_minor_description.not_nil!.downcase.gsub(/[^a-z0-9]+/, "_")

        # Default to .sql extension for new migrations
        extension = @migration_extension || "sql"

        # Generate filenames
        up_file = "migrations/#{timestamp}_#{safe_desc}.up.#{extension}"
        down_file = "migrations/#{timestamp}_#{safe_desc}.down.#{extension}"

        # Write migration files
        File.write(up_file, <<-SQL
      -- Migration #{timestamp}: #{@migration_minor_description}
      BEGIN;

      -- Add your migration SQL here

      END;
      SQL
        )

        File.write(down_file, <<-SQL
      -- Down Migration #{timestamp}: #{@migration_minor_description}
      BEGIN;

      -- Add your down migration SQL here

      END;
      SQL
        )

        puts "Created new migration files:"
        puts "  #{up_file}"
        puts "  #{down_file}"
      end
    end

    private def find_down_migration(version : String) : Path?
      down_paths = [Path["migrations/#{version}_*.down.sql"], Path["migrations/#{version}_*.down.psql"]]
      down_globs = down_paths.map { |p| Dir.glob(p) }.flatten
      down_globs.first?.try { |path| Path[path] }
    end

    private def get_migrations_to_rollback(db, migrate_to : Int64?) : Array(NamedTuple(version: String))
      query = <<-SQL
    SELECT version::TEXT
    FROM db.migration
    WHERE version #{migrate_to ? ">= $1" : "IS NOT NULL"}
    ORDER BY version DESC
  SQL

      args = migrate_to ? [migrate_to.to_i64] : [] of String
      db.query_all(query, args: args, as: {version: String})
    end

    private def ensure_migration_table(db)
      # Check if migrations table exists
      table_exists = db.query_one?("SELECT EXISTS (
      SELECT FROM pg_tables
      WHERE schemaname = 'db'
      AND tablename = 'migration'
    )", as: Bool)

      return if table_exists

      puts "Creating db.migration" if @config.verbose
      db.exec_all(<<-SQL
      BEGIN;
      CREATE SCHEMA IF NOT EXISTS db;

      CREATE TABLE db.migration (
        id SERIAL PRIMARY KEY,
        version BIGINT NOT NULL,
        filename text NOT NULL,
        description text NOT NULL,
        applied_at timestamp with time zone NOT NULL DEFAULT now(),
        duration_ms integer NOT NULL
      );
      CREATE INDEX migration_version_idx ON db.migration(version);

      ALTER TABLE db.migration ENABLE ROW LEVEL SECURITY;

      CREATE POLICY migration_authenticated_read ON db.migration
        FOR SELECT TO authenticated USING (true);
      END;
    SQL
      )
    end

    private def apply_migration(db, migration)
      if @config.verbose
        STDOUT.print "Migration #{migration.version} (#{migration.description}) "
        STDOUT.flush
      end

      # Check if this migration is already applied
      existing = db.query_one?(
        "SELECT version FROM db.migration WHERE version = $1",
        migration.version,
        as: Int64?
      )

      if existing
        STDOUT.puts "[already applied]" if @config.verbose
        return false
      end

      if @config.verbose
        STDOUT.print "[applying] "
        STDOUT.flush
      end

      start_time = Time.monotonic
      success = false

      case migration.extension
      when "sql"
        # Direct SQL execution
        begin
          sql_content = File.read(migration.path)
          db.transaction do |tx|
            tx.connection.exec_all(sql_content)
          end
          success = true
        rescue ex
          raise "Failed to apply SQL migration #{migration.path.basename}: #{ex.message}"
        end
      when "psql"
        # Execute via psql command (existing behavior)
        Dir.cd(@config.project_directory) do
          output = `./devops/manage-statbus.sh psql --variable=ON_ERROR_STOP=on < #{migration.path} 2>&1`
          success = $?.success?
          if @config.debug && !output.empty?
            STDOUT.puts output
          end
          raise "Failed to apply PSQL migration #{migration.path.basename}. Check the PostgreSQL logs for details." unless success
        end
      else
        raise "Unknown migration extension: #{migration.extension}"
      end

      if success
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i

        # Record successful migration
        db.exec(
          "INSERT INTO db.migration (version, filename, description, duration_ms)
         VALUES ($1, $2, $3, $4)",
          migration.version,
          migration.path.basename,
          migration.description,
          duration_ms
        )

        if @config.verbose
          STDOUT.puts "done (#{duration_ms}ms)"
        end
      end

      true
    end

    private def cleanup_migration_schema(db)
      db.transaction do |tx|
        tx.connection.exec("DROP TABLE IF EXISTS db.migration")
        tx.connection.exec("DROP SCHEMA IF EXISTS db CASCADE")
      end
      puts "Removed migration tracking table and schema" if @config.verbose
    end

    private def execute_down_migration(db, down_path : Path, version : String)
      Dir.cd(@config.project_directory) do
        migration = MigrationFile.parse(down_path)

        if @config.verbose
          STDOUT.print "Migration #{version} (#{migration.description}) "
          STDOUT.flush
        end

        delete_sql = <<-SQL
        DELETE FROM db.migration
          WHERE version = $1
          RETURNING version::TEXT;
      SQL

        # Check if migration file is empty (size 0)
        if File.size(down_path) == 0
          if @config.verbose
            STDOUT.puts "[empty - skipped]"
          end
          # Remove the migration record without running the file
          db.query_all(delete_sql, version, as: {version: String})
        else
          if @config.verbose
            STDOUT.print "[rolling back] "
            STDOUT.flush
          end

          # Start timing
          start_time = Time.monotonic

          success = false
          output = ""
          case migration.extension
          when "sql"
            # Direct SQL execution
            begin
              sql_content = File.read(down_path)
              db.transaction do |tx|
                tx.connection.exec_all(sql_content)
              end
              success = true
            rescue ex
              raise "Failed to roll back SQL migration #{down_path.basename}: #{ex.message}"
            end
          when "psql"
            # Execute via psql command
            output = `./devops/manage-statbus.sh psql --variable=ON_ERROR_STOP=on < #{down_path} 2>&1`
            success = $?.success?
            if @config.debug && !output.empty?
              STDOUT.puts output
            end
            raise "Failed to roll back PSQL migration #{down_path.basename}. Check the PostgreSQL logs for details." unless success
          else
            raise "Unknown migration extension: #{migration.extension}"
          end

          if success
            # Calculate duration in milliseconds
            duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i

            # Remove the migration record(s)
            db.query_all(delete_sql, version, as: {version: String})

            if @config.verbose
              STDOUT.puts "done (#{duration_ms}ms)"
              STDOUT.puts output if @config.debug && !output.empty?
            end
          else
            raise "Failed to roll back migration #{down_path}. Check the PostgreSQL logs for details."
          end
        end
      end
    end

    private struct MigrationFile
      property version : Int64
      property path : Path
      property description : String
      property is_up : Bool
      property extension : String

      def initialize(@version : Int64, @path : Path, @description : String, @is_up : Bool, @extension : String)
        @extension = @path.extension.lchop('.') if @extension.empty?
        unless ["sql", "psql"].includes?(@extension)
          raise "Invalid migration extension: '#{@extension}' Must be 'sql' or 'psql'"
        end
      end

      def self.parse(path : Path)
        filename = path.basename

        # Parse migration files: YYYYMMDDHHMMSS_description.(up|down).(sql|psql)
        if match = filename.match(/^(\d{14})_([^0-9].+)\.(up|down)\.(sql|psql)$/)
          version = match[1].to_i64
          # Validate timestamp format
          begin
            Time.parse(version.to_s, "%Y%m%d%H%M%S", Time::Location::UTC)
          rescue
            raise "Invalid timestamp format in migration filename: #{path}"
          end
          description = match[2]
          is_up = match[3] == "up"
          extension = match[4]

          return new(
            version: version,
            path: path,
            description: description,
            is_up: is_up,
            extension: extension
          )
        end

        raise "Invalid migration filename format: #{path} - expected YYYYMMDDHHMMSS_description.(up|down).sql"
      end
    end
  end
end
