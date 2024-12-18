require "http/client"
require "json"
require "digest/sha256"
require "time"
require "option_parser"
require "dir"
require "./config"
require "db"
require "pg"
require "file"
require "csv"

# The `Statbus` module is designed to manage and import data for a statistical business registry.
# It supports various operations like installation, management (start, stop, status), and data import.
class StatBus
  enum Mode
    Welcome
    Install
    Manage
    Import
    Migrate
  end
  enum ImportMode
    LegalUnit
    Establishment
  end
  enum ManageMode
    Start
    Stop
    Status
  end
  enum ImportStrategy
    Copy
    Insert
  end
  enum MigrateMode
    Up
    Down
    New
    Redo
  end
  # Mappings for a configuration, where every field is present.
  # Nil records the intention of not using an sql field
  # or not using a csv field.
  record ConfigFieldMapping, sql : String?, csv : String? do
    include JSON::Serializable
  end

  private struct MigrationFile
    property version : String
    property path : Path
    property description : String
    property is_up : Bool

    def initialize(@version : String, @path : Path, @description : String, @is_up : Bool)
    end

    def self.parse(path : Path)
      filename = path.basename

      # Parse migration files: YYYY_NNN_description.(up|down).sql
      if match = filename.match(/^([\d_]+?)_([^0-9].+)\.(up|down)\.sql$/)
        version = match[1]
        description = match[3]
        is_up = match[3] == "up"

        return new(
          version: version,
          path: path,
          description: description,
          is_up: is_up
        )
      end

      raise "Invalid migration filename format: #{path} - expected NNNN_description.(up|down).sql"
    end
  end

  # Mapping for SQL where only sql fields that map to an actual csv
  class SqlFieldMapping
    property sql : String
    property csv : String?
    property value : String?

    # Custom exception for invalid initialization
    class InitializationError < Exception; end

    def initialize(sql : String?, csv : String? = nil, value : String? = nil)
      if (sql.nil?)
        raise InitializationError.new("sql can not be nil")
      end

      @sql = sql.not_nil!
      @csv = csv
      @value = value

      # Ensure exactly one of csv or value is set
      if (csv.nil? && value.nil?) || (!csv.nil? && !value.nil?)
        raise InitializationError.new("Either csv xor value must be set, but not both.")
      end
    end

    def self.from_config_field_mapping(config_mapping : ConfigFieldMapping) : SqlFieldMapping?
      value : String | Nil = nil
      csv = config_mapping.csv

      if csv && /^'(.+)'$/ =~ csv
        value = $1
        csv = nil
      end

      sql = config_mapping.sql
      SqlFieldMapping.new(sql, csv: csv, value: value)
    end

    def to_config_field_mapping : ConfigFieldMapping
      # Escape single quotes in value if present
      escaped_value = value.try &.gsub("'", "''")

      # Check if there's an escaped value and format it as a quoted string if present
      csv_or_value = if escaped_value
                       "'#{escaped_value}'"
                     else
                       csv
                     end

      ConfigFieldMapping.new(sql: sql, csv: csv_or_value)
    end
  end

  @mode = Mode::Welcome
  @import_mode : ImportMode | Nil = nil
  @manage_mode : ManageMode | Nil = nil
  @name = "statbus"
  @verbose = false
  @delayed_constraint_checking = true
  @refresh_materialized_views = true
  @import_file_name : String | Nil = nil
  @config_field_mapping = Array(ConfigFieldMapping).new
  @config_file_path : Path | Nil = nil
  @sql_field_mapping = Array(SqlFieldMapping).new
  @working_directory = Dir.current
  @project_directory : Path

  private def initialize_project_directory : Path
    # First try from current directory
    current = Path.new(Dir.current)
    found = find_env_in_parents(current)

    if found.nil?
      # Fall back to executable path
      executable_path = Process.executable_path
      if executable_path.nil?
        current # Last resort: use current dir
      else
        exec_dir = Path.new(Path.new(executable_path).dirname)
        find_env_in_parents(exec_dir) || current
      end
    else
      found
    end
  end

  private def find_env_in_parents(start_path : Path) : Path?
    current = start_path
    while current.to_s != "/"
      if File.exists?(current.join(".env"))
        return current
      end
      current = current.parent
    end
    nil
  end

  @import_strategy = ImportStrategy::Copy
  @import_tag : String | Nil = nil
  @offset = 0
  @migrate_mode : MigrateMode | Nil = nil
  @migrate_all = true
  @migration_major_description : String | Nil = nil
  @migration_minor_description : String | Nil = nil
  @valid_from : String = Time.utc.to_s("%Y-%m-%d")
  @valid_to = "infinity"

  def initialize
    @project_directory = initialize_project_directory
    begin
      option_parser = build_option_parser
      option_parser.parse
      run(option_parser)
    rescue ex : ArgumentError
      puts ex
      exit 1
    end
  end

  def install
    puts "installing"
    # Download required files.
    Dir.cd(@project_directory) do
      if File.exists? ".env"
        puts "The config is already generated"
      elsif File.exists? ".env.example"
        puts "Generating a new config file"
        # Read .env.example
        # Generate random secrets and JWT's
        # Write .env
      else
        puts "Could not find template for .env"
      end
    end
    puts "installed"
  end

  def manage_start
    Dir.cd("../supabase_docker") do
      system "docker compose up -d"
    end
  end

  def manage_stop
    Dir.cd("../supabase_docker") do
      system "docker compose down"
    end
  end

  def manage_status
    # puts Dir.current
    # puts Process.executable_path
    # if Dir.exists?("")
    Dir.cd("../supabase_docker") do
      system "docker compose ps"
    end
  end

  def import_legal_units(import_file_name : String)
    puts "Importing legal units"
    sql_field_required_list = ["tax_ident"]
    sql_field_optional_list = [
      "name",
      "birth_date",
      "death_date",
      "physical_address_part1",
      "physical_address_part2",
      "physical_address_part3",
      "physical_postcode",
      "physical_postplace",
      "physical_region_code",
      "physical_region_path",
      "physical_country_iso_2",
      "postal_address_part1",
      "postal_address_part2",
      "postal_address_part3",
      "postal_postcode",
      "postal_postplace",
      "postal_region_code",
      "postal_region_path",
      "postal_country_iso_2",
      "primary_activity_category_code",
      "secondary_activity_category_code",
      "sector_code",
      "legal_form_code",
    ]
    upload_view_name = "import_legal_unit_era"
    import_common(import_file_name, sql_field_required_list, sql_field_optional_list, upload_view_name)
  end

  def import_establishments(import_file_name : String)
    puts "Importing establishments"
    sql_field_required_list = [
      "tax_ident",
    ]
    sql_field_optional_list = [
      "legal_unit_tax_ident",
      "name",
      "birth_date",
      "death_date",
      "physical_address_part1",
      "physical_address_part2",
      "physical_address_part3",
      "physical_postcode",
      "physical_postplace",
      "physical_region_code",
      "physical_region_path",
      "physical_country_iso_2",
      "postal_address_part1",
      "postal_address_part2",
      "postal_address_part3",
      "postal_postcode",
      "postal_postplace",
      "postal_region_code",
      "postal_region_path",
      "postal_country_iso_2",
      "primary_activity_category_code",
      "secondary_activity_category_code",
      "sector_code",
      "employees",
      "turnover",
    ]
    upload_view_name = "import_establishment_era"
    import_common(import_file_name, sql_field_required_list, sql_field_optional_list, upload_view_name)
  end

  private def import_common(import_file_name, sql_field_required_list, sql_field_optional_list, upload_view_name)
    # Find .env and load required secrets
    Dir.cd(@project_directory) do
      config = StatBusConfig.new(@project_directory, @verbose)
      puts "Import data to #{config.connection_string}" if @verbose

      sql_cli_provided_fields = ["valid_from", "valid_to", "tag_path"]
      sql_fields_list = sql_cli_provided_fields + sql_field_required_list + sql_field_optional_list
      file_stream =
        Dir.cd(@working_directory) do
          File.open(import_file_name)
        end
      csv_stream = CSV.new(file_stream, headers: true, separator: ',', quote_char: '"')
      csv_fields_list = csv_stream.headers
      # For every equal header, insert a mapping.
      sql_field_required = sql_field_required_list.to_set
      puts "sql_field_required #{sql_field_required}" if @verbose
      sql_fields = sql_fields_list.to_set
      puts "sql_field #{sql_fields}" if @verbose
      csv_fields = csv_fields_list.to_set
      puts "csv_fields #{csv_fields}" if @verbose
      common_fields = sql_fields & csv_fields
      puts "common_fields #{common_fields}" if @verbose
      common_fields.each do |common_field|
        @config_field_mapping.push(ConfigFieldMapping.new(sql: common_field, csv: common_field))
      end
      puts "@config_field_mapping #{@config_field_mapping}" if @verbose
      puts "@sql_field_mapping only common fields #{@sql_field_mapping}" if @verbose
      @config_field_mapping.each do |mapping|
        if !(mapping.csv.nil? || mapping.sql.nil?)
          @sql_field_mapping.push(SqlFieldMapping.from_config_field_mapping(mapping))
        end
      end
      puts "@sql_field_mapping #{@sql_field_mapping}" if @verbose
      mapped_sql_field = @sql_field_mapping.map(&.sql).to_set
      puts "mapped_sql_field #{mapped_sql_field}" if @verbose
      mapped_csv_field = @config_field_mapping.map(&.csv).to_set
      puts "mapped_csv_field #{mapped_csv_field}" if @verbose
      missing_required_sql_fields = sql_field_required - mapped_sql_field

      ignored_sql_field = @config_field_mapping.select { |m| m.csv.nil? }.map(&.sql).to_set
      puts "ignored_sql_field #{ignored_sql_field}" if @verbose
      ignored_csv_field = @config_field_mapping.select { |m| m.sql.nil? }.map(&.csv).to_set
      puts "ignored_csv_field #{ignored_csv_field}" if @verbose
      # Check the fields
      missing_config_sql_fields = sql_fields - sql_cli_provided_fields - mapped_sql_field - ignored_sql_field
      puts "missing_config_sql_fields #{missing_config_sql_fields}" if @verbose

      if missing_required_sql_fields.any? || missing_config_sql_fields.any?
        # Build the empty mappings for displaying a starting point to the user:
        # For every absent header, insert an absent mapping.
        missing_config_sql_fields.each do |sql_field|
          @config_field_mapping.push(ConfigFieldMapping.new(sql: sql_field, csv: "null"))
        end
        missing_config_csv_fields = csv_fields - mapped_csv_field - ignored_csv_field
        puts "missing_config_csv_fields #{missing_config_csv_fields}" if @verbose
        missing_config_csv_fields.each do |csv_field|
          @config_field_mapping.push(ConfigFieldMapping.new(sql: "null", csv: csv_field))
        end
        # Now there is a mapping for every field.
        # This mapping can be printed for the user.
        puts "Example mapping:"
        Dir.cd(@working_directory) do
          if !@config_file_path.nil?
            if !File.exists?(@config_file_path.not_nil!)
              File.write(
                @config_file_path.not_nil!,
                @config_field_mapping.to_pretty_json
              )
            end
          end
        end

        raise ArgumentError.new("Missing sql fields #{missing_config_sql_fields.to_a.to_pretty_json} you need to add a mapping")
      end

      puts "@config_field_mapping = #{@config_field_mapping}" if @verbose

      Dir.cd(@working_directory) do
        if !@config_file_path.nil?
          if !File.exists?(@config_file_path.not_nil!)
            puts "Writing file #{@config_file_path}"
            File.write(
              @config_file_path.not_nil!,
              @config_field_mapping.to_pretty_json
            )
            puts @config_field_mapping.to_pretty_json
          end
        end
      end

      db_connection_string = config.connection_string
      puts db_connection_string if @verbose
      DB.connect(db_connection_string) do |db|
        if !@import_tag.nil?
          tag = db.query_one?("
            SELECT id, path::text, name, context_valid_from::text, context_valid_to::text
            FROM public.tag
            WHERE path = $1", @import_tag,
            as: {id: Int32, path: String, name: String, context_valid_from: String?, context_valid_to: String?}
          )
          if tag.nil?
            raise ArgumentError.new("Unknown tag #{@import_tag}")
          elsif tag[:context_valid_from].nil? || tag[:context_valid_to].nil?
            raise ArgumentError.new("Tag #{tag[:path]} is missing context dates")
          end
          puts "Found tag #{tag}" if @verbose
          @valid_from = tag[:context_valid_from].not_nil!
          @valid_to = tag[:context_valid_to].not_nil!
        end

        @sql_field_mapping = [
          SqlFieldMapping.new(sql: "valid_from", value: @valid_from),
          SqlFieldMapping.new(sql: "valid_to", value: @valid_to),
          if !@import_tag.nil?
            SqlFieldMapping.new(sql: "tag_path", value: @import_tag)
          end,
        ].compact + @sql_field_mapping

        puts "@sql_field_mapping = #{@sql_field_mapping}" if @verbose

        # Sort header mappings based on position in sql_fields_list
        @sql_field_mapping.sort_by! do |mapping|
          index = sql_fields_list.index(mapping.sql)
          if index.nil?
            raise ArgumentError.new("Found mapping for non existing sql field #{mapping.sql}")
          end
          # Every field found is order according to its position
          {1, index.not_nil!, ""}
        end

        sql_fields_str = @sql_field_mapping.map do |mapping|
          if !mapping.sql.nil?
            db.escape_identifier(mapping.sql.not_nil!)
          end
        end.compact.join(",")
        puts "sql_fields_str = #{sql_fields_str}" if @verbose

        case @import_strategy
        when ImportStrategy::Copy
          copy_stream = db.exec_copy "COPY public.#{upload_view_name}(#{sql_fields_str}) FROM STDIN"
          start_time = Time.monotonic
          row_count = 0

          iterate_csv_stream(csv_stream) do |sql_row, csv_row|
            sql_row.any? do |value|
              if !value.nil? && value.includes?("\t")
                raise ArgumentError.new("Found illegal character TAB \\t in row #{csv_row}")
              end
            end
            sql_text = sql_row.join("\t")
            puts "Uploading #{sql_text}" if @verbose
            copy_stream.puts sql_text
            row_count += 1
            nil
          end
          puts "Waiting for processing" if @verbose
          copy_stream.close

          total_duration = Time.monotonic - start_time
          total_rows_per_second = row_count / total_duration.total_seconds
          puts "Total rows processed: #{row_count}"
          puts "Total time: #{total_duration.total_seconds.round(2)} seconds (#{total_rows_per_second.round(2)} rows/second)"

          db.close
        when ImportStrategy::Insert
          sql_args = (1..(@sql_field_mapping.size)).map { |i| "$#{i}" }.join(",")
          sql_statement = "INSERT INTO public.#{upload_view_name}(#{sql_fields_str}) VALUES(#{sql_args})"
          puts "sql_statement = #{sql_statement}" if @verbose
          db.exec "BEGIN;"
          # Set a config that prevents inner trigger functions form activating constraints,
          # make the deferral moot.
          if @delayed_constraint_checking
            db.exec "SET LOCAL statbus.constraints_already_deferred TO 'true';"
            db.exec "SET CONSTRAINTS ALL DEFERRED;"
          end
          start_time = Time.monotonic
          batch_start_time = start_time
          row_count = 0
          insert = db.build sql_statement
          batch_size = 10000
          batch_item = 0
          iterate_csv_stream(csv_stream) do |sql_row, csv_row|
            batch_item += 1
            row_count += 1
            puts "Uploading #{sql_row}" if @verbose
            insert.exec(args: sql_row)
            -> {
              if (batch_item % batch_size) == 0
                puts "Commit-ing changes"
                if @delayed_constraint_checking
                  db.exec "SET CONSTRAINTS ALL IMMEDIATE;"
                end
                db.exec "END;"

                batch_duration = Time.monotonic - batch_start_time
                batch_rows_per_second = batch_size / batch_duration.total_seconds
                puts "Processed #{batch_size} rows in #{batch_duration.total_seconds.round(2)} seconds (#{batch_rows_per_second.round(2)} rows/second)"
                batch_start_time = Time.monotonic

                if @refresh_materialized_views
                  start_refresh_time = Time.monotonic
                  puts "Refreshing statistical_unit and other materialized views"
                  db.exec "SELECT statistical_unit_refresh_now();"
                  refresh_duration = Time.monotonic - start_refresh_time
                  puts "Refreshing completed (#{refresh_duration.total_seconds.round(2)} seconds)"
                end
                db.exec "BEGIN;"
                if @delayed_constraint_checking
                  db.exec "SET LOCAL statbus.constraints_already_deferred TO 'true';"
                  db.exec "SET CONSTRAINTS ALL DEFERRED;"
                end
                insert = db.build sql_statement
              end
            }
          end
          puts "Commit-ing changes"
          if @delayed_constraint_checking
            db.exec "SET CONSTRAINTS ALL IMMEDIATE;"
          end
          db.exec "END;"

          total_duration = Time.monotonic - start_time
          total_rows_per_second = row_count / total_duration.total_seconds
          puts "Total rows processed: #{row_count}"
          puts "Total time: #{total_duration.total_seconds.round(2)} seconds (#{total_rows_per_second.round(2)} rows/second)"

          if @refresh_materialized_views
            puts "Refreshing statistical_unit and other materialized views"
            db.exec "SELECT statistical_unit_refresh_now();"
          end
          db.close
        end
      end
    end
  end

  private def iterate_csv_stream(csv_stream)
    row_count = 0
    while csv_stream.next
      row_count += 1
      if 0 < @offset
        if row_count < @offset
          next
        elsif row_count == @offset
          puts "Continuing after  #{row_count.format(delimiter: '_')} rows"
          next
        end
      end
      csv_row = csv_stream.row
      sql_row = @sql_field_mapping.map do |mapping|
        csv_value =
          if mapping.csv.nil?
            mapping.value || ""
          else
            csv_row[mapping.csv.not_nil!]
          end
        if csv_value.nil?
          nil
        elsif csv_value.strip == ""
          nil
        else
          csv_value.strip
        end
      end
      post_process = yield(sql_row, csv_row)
      if (row_count % 1000) == 0
        puts "Uploaded #{row_count.format(delimiter: '_')} rows"
      end
      if !post_process.nil?
        post_process.call
      end
    end
    puts "Wrote #{row_count} rows"
  end

  private def build_option_parser
    OptionParser.new do |parser|
      parser.banner = "Usage: #{@name} [subcommand] [arguments]"
      parser.on("-v", "--verbose", "Enable verbose output") { @verbose = true }
      parser.on("install", "Install StatBus") do
        @mode = Mode::Install
        parser.banner = "Usage: #{@name} install [arguments]"
      end
      parser.on("manage", "Manage installed StatBus") do
        @mode = Mode::Manage
        parser.banner = "Usage: #{@name} manage [arguments]"
        parser.on("start", "Start StatBus with docker compose") do
          @manage_mode = ManageMode::Start
        end
        parser.on("stop", "Stop StatBus with docker compose") do
          @manage_mode = ManageMode::Stop
        end
        parser.on("status", "Status on StatBus") do
          @manage_mode = ManageMode::Status
        end
      end
      parser.on("import", "Import into installed StatBus") do
        @mode = Mode::Import
        parser.banner = "Usage: #{@name} import [legal_unit|establishment] [arguments]"
        parser.on("legal_unit", "Import legal units") do
          parser.banner = "Usage: #{@name} import legal_unit [arguments]"
          @import_mode = ImportMode::LegalUnit
        end
        parser.on("establishment", "Import legal units") do
          parser.banner = "Usage: #{@name} import establishment [arguments]"
          @import_mode = ImportMode::Establishment
        end
        parser.on("-f FILENAME", "--file=FILENAME", "The file to read from") do |file_name|
          import_file_name = file_name
          @import_file_name = import_file_name
          puts "Loading data from #{@import_file_name}"
        end
        parser.on("-o offset", "--offset=NUMBER", "Number of rows to skip") do |offset|
          @offset = offset.to_i(underscore: true)
        end
        parser.on("-s STRATEGY", "--strategy=STRATEGY", "Use fast bulk \"copy\" or slower \"insert\" with earlier error messages.") do |strategy|
          case strategy
          when "copy"
            @import_strategy = ImportStrategy::Copy
          when "insert"
            @import_strategy = ImportStrategy::Insert
          else
            puts "Unknown strategy: use COPY or INSERT"
            puts parser
            exit(1)
          end
        end
        parser.on("-t path.for.tag", "--tag=path.for.tag", "Insert scoped to a tag - limits valid_to, valid_from and adds the tag") do |tag|
          @import_tag = tag
        end
        parser.on("-c FILENAME", "--config=FILENAME", "A config file with field mappings. Will be written to with an example if the file does not exist.") do |file_name|
          Dir.cd(@working_directory) do
            @config_file_path = Path.new(file_name)
            if File.exists?(@config_file_path.not_nil!)
              puts "Loading mapping from #{file_name}"
              config_data = File.read(@config_file_path.not_nil!)
              @config_field_mapping = Array(ConfigFieldMapping).from_json(config_data)
            else
              STDERR.puts "Could not find #{@config_file_path}"
            end
          end
        end
        parser.on("-m NEW=OLD", "--mapping=NEW=OLD", "A field name mapping, possibly null if the field is unused. A constant in single quotes is possible instead of an csv field.") do |mapping|
          sql, csv = mapping.split("=").map do |field_name|
            if field_name.empty? || field_name == "nil" || field_name == "null"
              nil
            else
              field_name
            end
          end
          @config_field_mapping.push(ConfigFieldMapping.new(sql: sql, csv: csv))
        end
        parser.on("--immediate-constraint-checking", "Check constraints for each record immediately") do
          @delayed_constraint_checking = false
        end
        parser.on("--skip-refresh-of-materialized-views", "Avoid refreshing materialized views during and after load") do
          @refresh_materialized_views = false
        end
      end
      parser.on("migrate", "Run database migrations") do
        @mode = Mode::Migrate
        parser.banner = "Usage: #{@name} migrate [arguments]"
        parser.on("up", "Run all pending migrations") do
          @migrate_mode = MigrateMode::Up
          @migrate_all = true
          parser.on("one", "Run one up migration") do
            @migrate_all = false
          end
        end
        parser.on("new", "Create a new migration file") do
          @migrate_mode = MigrateMode::New
          parser.on("-d DESC", "--description=DESC", "Description for the migration") do |desc|
            @migration_minor_description = desc
          end
        end
        parser.on("down", "Roll back the last applied migration") do
          @migrate_mode = MigrateMode::Down
          @migrate_all = false
          parser.on("all", "Run all down migrations") do
            @migrate_all = true
          end
        end
        parser.on("redo", "Roll back last migration and reapply it") do
          @migrate_mode = MigrateMode::Redo
        end
      end
      parser.on("welcome", "Print a greeting message") do
        @mode = Mode::Welcome
        parser.banner = "Usage: #{@name} welcome"
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end
  end

  private def ensure_migration_table(db)
    # Check if migrations table exists
    table_exists = db.query_one?("SELECT EXISTS (
      SELECT FROM pg_tables
      WHERE schemaname = 'db'
      AND tablename = 'migration'
    )", as: Bool)

    return if table_exists

    puts "Creating db.migration" if @verbose
    db.exec_all(<<-SQL
      BEGIN;
      CREATE SCHEMA IF NOT EXISTS db;

      CREATE TABLE db.migration (
        id SERIAL PRIMARY KEY,
        version text NOT NULL,
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
    if @verbose
      STDOUT.print "Migration #{migration.version} (#{migration.description}) "
      STDOUT.flush
    end

    # Check if this migration is already applied
    existing = db.query_one?(
      "SELECT version FROM db.migration WHERE version = $1",
      migration.version,
      as: String?
    )

    if existing
      STDOUT.puts "[already applied]" if @verbose
      return false
    end

    if @verbose
      STDOUT.print "[applying] "
      STDOUT.flush
    end

    # Start timing
    start_time = Time.monotonic

    # Use system command to execute psql with the migration file
    Dir.cd(@project_directory) do
      result = system("./devops/manage-statbus.sh psql --variable=ON_ERROR_STOP=on < #{migration.path}")
      if result
        # Calculate duration in milliseconds
        duration_ms = (Time.monotonic - start_time).total_milliseconds.to_i

        # Record successful migration in migrations table
        db.exec(
          "INSERT INTO db.migration (version, filename, description, duration_ms)
           VALUES ($1, $2, $3, $4)",
          migration.version,
          migration.path.basename,
          migration.description,
          duration_ms
        )

        STDOUT.puts "done (#{duration_ms}ms)" if @verbose
      else
        raise "Failed to apply migration #{migration.path.basename}. Check the PostgreSQL logs for details."
      end
    end

    true
  end

  private def migrate_up
    Dir.cd(@project_directory) do
      config = StatBusConfig.new(@project_directory, @verbose)
      migration_paths = [Path["migrations/**/*.up.sql"]]
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
          # Stop if we've already applied one migration and we're in "one" mode
          if !@migrate_all && applied_count > 0
            break
          end

          if apply_migration(db, migration)
            applied_count += 1
          end
        end

        # Notify PostgREST to reload config and schema after all migrations
        if applied_count > 0
          db.transaction do |tx|
            puts "Notifying PostgREST to reload with changes." if @verbose
            tx.connection.exec("NOTIFY pgrst, 'reload config'")
            tx.connection.exec("NOTIFY pgrst, 'reload schema'")
          end
        end
      end
    end
  end

  private def run(option_parser : OptionParser)
    case @mode
    when Mode::Welcome
      puts "StatBus is a locally installable STATistical BUSiness registry"
    when Mode::Install
      install
    when Mode::Manage
      case @manage_mode
      when ManageMode::Start
        manage_start
      when ManageMode::Stop
        manage_stop
      when ManageMode::Status
        manage_status
      else
        puts "Unknown manage mode #{@manage_mode}"
        # puts parser
        exit(1)
      end
    when Mode::Import
      if @import_file_name.nil?
        STDERR.puts "missing required name of file to read from"
        # puts parser
        exit(1)
      else
        case @import_mode
        when ImportMode::LegalUnit
          import_legal_units(@import_file_name.not_nil!)
        when ImportMode::Establishment
          import_establishments(@import_file_name.not_nil!)
        else
          puts "Unknown import mode #{@import_mode}"
          # puts parser
          exit(1)
        end
      end
    when Mode::Migrate
      case @migrate_mode
      when MigrateMode::Up
        migrate_up
      when MigrateMode::Down
        migrate_down
      when MigrateMode::New
        create_new_migration
      when MigrateMode::Redo
        @migrate_all = false # Ensure we only do one migration
        migrate_down
        migrate_up
      else
        STDERR.puts "Unknown migrate mode #{@migrate_mode}"
        exit(1)
      end
    else
      puts "Unknown mode #{@mode}"
    end
  end

  private def create_new_migration
    Dir.cd(@project_directory) do
      if @migration_minor_description.nil?
        STDERR.puts "Missing required description for migration. Use:"
        STDERR.puts "  -d/--description to specify the migration description"
        exit(1)
      end

      # Get current year
      current_year = Time.utc.year.to_s

      # Find latest migration number for this year
      migration_paths = Dir.glob("migrations/#{current_year}_*.up.sql")
      latest_number = migration_paths.map do |path|
        if match = Path[path].basename.match(/^#{current_year}_(\d{3})_/)
          match[1].to_i
        else
          0
        end
      end.max || 0

      # Generate next migration number
      next_number = (latest_number + 1).to_s.rjust(3, '0')

      # Create safe description
      safe_desc = @migration_minor_description.not_nil!.downcase.gsub(/[^a-z0-9]+/, "_")

      # Generate filenames
      up_file = "migrations/#{current_year}_#{next_number}_#{safe_desc}.up.sql"
      down_file = "migrations/#{current_year}_#{next_number}_#{safe_desc}.down.sql"

      # Write migration files
      File.write(up_file, <<-SQL
        -- Migration #{current_year}_#{next_number}: #{@migration_minor_description}
        BEGIN;

        -- Add your migration SQL here

        END;
        SQL
      )

      File.write(down_file, <<-SQL
        -- Down Migration #{current_year}_#{next_number}: #{@migration_minor_description}
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

  private def migrate_down
    Dir.cd(@project_directory) do
      config = StatBusConfig.new(@project_directory, @verbose)

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

        if @migrate_all
          # Get all migrations in reverse order by version
          while (last_migration = db.query_one?(
                  "SELECT version, filename
                   FROM db.migration
                   ORDER BY version DESC
                   LIMIT 1",
                  as: {version: String, filename: String}
                ))
            version = last_migration[:version]
            down_paths = [] of Path
            down_paths << Path["migrations/#{version}_*.down.sql"]

            down_globs = down_paths.map { |p| Dir.glob(p) }.flatten
            if found_path = down_globs.first?
              execute_down_migration(db, Path[found_path], version.to_s)
            else
              raise "Missing down migration for #{version}"
            end
          end

          # After all migrations are down, clean up
          cleanup_migration_schema(db)
          return
        end

        # Get the last applied migration
        last_migration = db.query_one?(
          "SELECT version
           FROM db.migration
           ORDER BY version DESC
           LIMIT 1",
          as: {version: String}
        )

        if last_migration.nil?
          # No more migrations, clean up
          cleanup_migration_schema(db)
          return
        end

        version = last_migration[:version]

        # Look for corresponding down migration
        down_paths = [] of Path
        down_paths << Path["migrations/#{version}_*.down.sql"]
        down_globs = down_paths.map { |p| Dir.glob(p) }.flatten
        if found_path = down_globs.first?
          execute_down_migration(db, Path[found_path], version)
        else
          raise "Missing down migration file for version #{version}. Expected file matching pattern: migrations/#{version}_*.down.sql"
        end
      end
    end
  end

  private def cleanup_migration_schema(db)
    db.transaction do |tx|
      tx.connection.exec("DROP TABLE IF EXISTS db.migration")
      tx.connection.exec("DROP SCHEMA IF EXISTS db CASCADE")
    end
    puts "Removed migration tracking table and schema" if @verbose
  end

  private def execute_down_migration(db, down_path : Path, version : String)
    Dir.cd(@project_directory) do
      migration = MigrationFile.parse(down_path)
      result = system("./devops/manage-statbus.sh psql --variable=ON_ERROR_STOP=on < #{down_path}")
      if result
        # Remove the migration record(s)
        versions = db.query_all(<<-SQL, version, as: {version: String})
          DELETE FROM db.migration
             WHERE version = $1
             RETURNING version;
          SQL

        if @verbose
          versions = versions.map { |m| m[:version] }
          STDOUT.puts "Rolled back migration(s) #{versions.join(", ")} "
        end

        # Notify PostgREST to reload
        db.transaction do |tx|
          puts "Notifying PostgREST to reload with changes." if @verbose
          tx.connection.exec("NOTIFY pgrst, 'reload config'")
          tx.connection.exec("NOTIFY pgrst, 'reload schema'")
        end
      else
        raise "Failed to roll back migration #{down_path}. Check the PostgreSQL logs for details."
      end
    end
  end
end

StatBus.new
