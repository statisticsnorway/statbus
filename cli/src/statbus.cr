require "http/client"
require "json"
require "digest/sha256"
require "./dotenv"
require "time"
require "option_parser"
require "dir"
require "./config"
require "db"
require "pg"
require "file"
require "csv"
require "yaml"
require "jwt"

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
    CreateUsers
    GenerateConfig
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
    Convert
  end
  # Mappings for a configuration, where every field is present.
  # Nil records the intention of not using an sql field
  # or not using a csv field.
  record ConfigFieldMapping, sql : String?, csv : String? do
    include JSON::Serializable
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
  @debug = false
  @delayed_constraint_checking = true
  @refresh_materialized_views = true
  @import_file_name : String | Nil = nil
  @config_field_mapping = Array(ConfigFieldMapping).new
  @config_field_mapping_file_path : Path | Nil = nil
  @sql_field_mapping = Array(SqlFieldMapping).new
  @working_directory = Dir.current
  @project_directory : Path

  private def initialize_project_directory : Path
    # First try from current directory
    current = Path.new(Dir.current)
    found = find_statbus_in_parents(current)

    if found.nil?
      # Fall back to executable path
      executable_path = Process.executable_path
      if executable_path.nil?
        current # Last resort: use current dir
      else
        exec_dir = Path.new(Path.new(executable_path).dirname)
        find_statbus_in_parents(exec_dir) || current
      end
    else
      found
    end
  end

  private def find_statbus_in_parents(start_path : Path) : Path?
    current = start_path
    while current.to_s != "/"
      # The .statbus is an empty marker file placed in the statbus directory.
      if File.exists?(current.join(".statbus"))
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
  @migrate_to : Int64? = nil
  @convert_start_date = Time.utc(2024, 1, 1)
  @convert_spacing = 1.day
  @migration_major_description : String | Nil = nil
  @migration_minor_description : String | Nil = nil
  @migration_extension : String | Nil = nil
  @valid_from : String = Time.utc.to_s("%Y-%m-%d")
  @valid_to = "infinity"
  @user_email : String | Nil = nil

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
      else
        puts "Could not find template for .env"
        manage_generate_config
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
          if !@config_field_mapping_file_path.nil?
            if !File.exists?(@config_field_mapping_file_path.not_nil!)
              File.write(
                @config_field_mapping_file_path.not_nil!,
                @config_field_mapping.to_pretty_json
              )
            end
          end
        end

        raise ArgumentError.new("Missing sql fields #{missing_config_sql_fields.to_a.to_pretty_json} you need to add a mapping")
      end

      puts "@config_field_mapping = #{@config_field_mapping}" if @verbose

      Dir.cd(@working_directory) do
        if !@config_field_mapping_file_path.nil?
          if !File.exists?(@config_field_mapping_file_path.not_nil!)
            puts "Writing file #{@config_field_mapping_file_path}"
            File.write(
              @config_field_mapping_file_path.not_nil!,
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

        # Verify user exists
        user = db.query_one?(
          "SELECT id::TEXT FROM auth.users WHERE email = $1",
          @user_email,
          as: {id: String}
        )

        if user.nil?
          raise ArgumentError.new("User with email #{@user_email} not found")
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
          db.exec "CALL test.set_user_from_email($1)", @user_email
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
          db.exec "CALL test.set_user_from_email($1)", @user_email
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
                db.exec "CALL test.set_user_from_email($1)", @user_email
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
      parser.on("-d", "--debug", "Enable debug output") { @debug = true }
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
        parser.on("create-users", "Create users from .users.yml file") do
          @manage_mode = ManageMode::CreateUsers
        end
        parser.on("generate-config", "Generate configuration files") do
          @manage_mode = ManageMode::GenerateConfig
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
            @config_field_mapping_file_path = Path.new(file_name)
            if File.exists?(@config_field_mapping_file_path.not_nil!)
              puts "Loading mapping from #{file_name}"
              config_data = File.read(@config_field_mapping_file_path.not_nil!)
              @config_field_mapping = Array(ConfigFieldMapping).from_json(config_data)
            else
              STDERR.puts "Could not find #{@config_field_mapping_file_path}"
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
        parser.on("-u EMAIL", "--user=EMAIL", "Email of the user performing the import") do |user_email|
          @user_email = user_email
        end
      end
      parser.on("migrate", "Run database migrations") do
        @mode = Mode::Migrate
        parser.banner = "Usage: #{@name} migrate [arguments]"
        parser.on("up", "Run pending migrations") do
          @migrate_mode = MigrateMode::Up
          @migrate_all = true
          parser.on("--to VERSION", "Migrate up to specific version") do |version|
            @migrate_to = version.to_i64
          end
          parser.on("one", "Run one up migration") do
            @migrate_all = false
          end
        end
        parser.on("new", "Create a new migration file") do
          @migrate_mode = MigrateMode::New
          parser.on("-d DESC", "--description=DESC", "Description for the migration") do |desc|
            @migration_minor_description = desc
          end
          parser.on("-e EXT", "--extension=EXT", "File extension for the migration (sql or psql, defaults to sql)") do |ext|
            if ext != "sql" && ext != "psql"
              STDERR.puts "Error: Extension must be 'sql' or 'psql'"
              exit(1)
            end
            @migration_extension = ext
          end
        end
        parser.on("down", "Roll back migrations") do
          @migrate_mode = MigrateMode::Down
          @migrate_all = false
          parser.on("--to VERSION", "Roll back to specific version") do |version|
            @migrate_to = version.to_i64
          end
          parser.on("all", "Run all down migrations") do
            @migrate_all = true
          end
        end
        parser.on("redo", "Roll back last migration and reapply it") do
          @migrate_mode = MigrateMode::Redo
        end
        parser.on("convert", "Convert existing migrations to timestamp format") do
          @migrate_mode = MigrateMode::Convert
          parser.on("--start=DATE", "Start date for conversion (default: 2024-01-01)") do |date|
            @convert_start_date = Time.parse(date, "%Y-%m-%d", Time::Location::UTC)
          end
          parser.on("--spacing=DAYS", "Days between migrations (default: 1)") do |days|
            @convert_spacing = days.to_i.days
          end
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
    if @verbose
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
      STDOUT.puts "[already applied]" if @verbose
      return false
    end

    if @verbose
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
      Dir.cd(@project_directory) do
        output = `./devops/manage-statbus.sh psql --variable=ON_ERROR_STOP=on < #{migration.path} 2>&1`
        success = $?.success?
        if @debug && !output.empty?
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

      if @verbose
        STDOUT.puts "done (#{duration_ms}ms)"
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
      when ManageMode::CreateUsers
        create_users
      when ManageMode::GenerateConfig
        manage_generate_config
      else
        puts "Unknown manage mode #{@manage_mode}"
        # puts parser
        exit(1)
      end
    when Mode::Import
      if @import_file_name.nil? || @user_email.nil?
        if @import_file_name.nil?
          STDERR.puts "missing required name of file to read from"
        end
        if @user_email.nil?
          STDERR.puts "missing required user email (use -u or --user)"
        end
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
      when MigrateMode::Convert
        convert_migrations
      else
        STDERR.puts "Unknown migrate mode #{@migrate_mode}"
        exit(1)
      end
    else
      puts "Unknown mode #{@mode}"
    end
  end

  private def convert_migrations
    Dir.cd(@project_directory) do
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

  private def create_new_migration
    Dir.cd(@project_directory) do
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
            puts "Notifying PostgREST to reload with changes." if @verbose
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

  private def create_users
    Dir.cd(@project_directory) do
      config = StatBusConfig.new(@project_directory, @verbose)

      if !File.exists?(".users.yml")
        STDERR.puts "Error: .users.yml file not found"
        exit(1)
      end

      DB.connect(config.connection_string) do |db|
        available_roles : Array(String) = ["super_user", "regular_user", "restricted_user", "external_user"]
        begin
          Dir.cd(@project_directory) do
            available_roles = db.query_all(
              "SELECT unnest(enum_range(NULL::public.statbus_role_type))::text AS role",
              as: {role: String}
            ).map { |r| r[:role] }
          end
        rescue ex
          STDERR.puts "Warning: Could not load roles from database: #{ex.message}"
          available_roles = ["super_user", "regular_user", "restricted_user", "external_user"]
        end

        # Read users from YAML file
        users_yaml = File.read(".users.yml")
        users = YAML.parse(users_yaml)

        users.as_a.each do |user|
          email = user["email"].as_s
          password = user["password"].as_s
          # Default to regular_user if role not specified
          role = user["role"]?.try(&.as_s) || "regular_user"

          # Validate role
          if !available_roles.includes?(role)
            STDERR.puts "Error: Invalid role '#{role}' for user #{email}"
            STDERR.puts "Available roles: #{available_roles.join(", ")}"
            exit(1)
          end

          puts "Creating user: #{email} with role: #{role}" if @verbose

          db.exec(
            "SELECT * FROM public.statbus_user_create($1, $2, $3)",
            email,
            role,
            password
          )
        end
      end
    end
  end

  # Ref. https://forum.crystal-lang.org/t/is-this-a-good-way-to-generate-a-random-string/6986/2
  private def random_string(len) : String
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    String.new(len) do |bytes|
      bytes.to_slice(len).fill { chars.to_slice.sample }
      {len, len}
    end
  end

  # Type-safe credentials structure
  record CredentialsEnv,
    postgres_password : String,
    jwt_secret : String,
    dashboard_username : String,
    dashboard_password : String,
    anon_key : String,
    service_role_key : String

  # Type-safe configuration structure
  record ConfigEnv,
    deployment_slot_name : String,
    deployment_slot_code : String,
    deployment_slot_port_offset : String,
    statbus_url : String,
    browser_supabase_url : String,
    server_supabase_url : String,
    seq_server_url : String,
    seq_api_key : String,
    slack_token : String

  # Configuration values that are derived from other settings
  record DerivedEnv,
    app_port : Int32,
    app_bind_address : String,
    supabase_port : Int32,
    supabase_bind_address : String,
    db_public_localhost_port : String,
    version : String,
    site_url : String,
    api_external_url : String,
    supabase_public_url : String,
    deployment_user : String,
    domain : String,
    enable_email_signup : Bool,
    enable_email_autoconfirm : Bool,
    disable_signup : Bool,
    studio_default_project : String

  private def manage_generate_config
    Dir.cd(@project_directory) do
      credentials_file = Path.new(".env.credentials")
      if File.exists?(credentials_file)
        puts "Using existing credentials from #{credentials_file}" if @verbose
      else
        puts "Generating new credentials in #{credentials_file}" if @verbose
      end

      # Generate or read existing credentials

      credentials = Dotenv.using(credentials_file) do |credentials_env|
        jwt_secret = credentials_env.generate("JWT_SECRET") { random_string(32) }

        # Generate JWT tokens
        # While the JWT tokens are calculated, the way Supabase is configured, it seems it does a TEXTUAL
        # equality check of the ANON JWT, and not an actual secret based calculation.
        # so if the JWT token is generated again, with a different timestamp, even if it is signed
        # with the same secret, it fails.
        # Therefore we store the derived JWT tokens as a credential, because it can not change without
        # invalidating the deployed or copied tokens. 🤦‍♂️

        # Issued At Time: Current timestamp in seconds since the Unix epoch
        iat = Time.utc.to_unix
        # Expiration Time: Calculate exp as iat plus the seconds in 5 years
        exp = iat + (5 * 365 * 24 * 60 * 60) # 5 years

        anon_payload = {
          role: "anon",
          iss:  "supabase",
          iat:  iat,
          exp:  exp,
        }

        service_role_payload = {
          role: "service_role",
          iss:  "supabase",
          iat:  iat,
          exp:  exp,
        }

        anon_key = JWT.encode(anon_payload, jwt_secret, JWT::Algorithm::HS256)
        service_role_key = JWT.encode(service_role_payload, jwt_secret, JWT::Algorithm::HS256)

        CredentialsEnv.new(
          postgres_password: credentials_env.generate("POSTGRES_PASSWORD") { random_string(20) },
          jwt_secret: jwt_secret,
          dashboard_username: credentials_env.generate("DASHBOARD_USERNAME") { "admin" },
          dashboard_password: credentials_env.generate("DASHBOARD_PASSWORD") { random_string(20) },
          anon_key: credentials_env.generate("ANON_KEY") { anon_key },
          service_role_key: credentials_env.generate("SERVICE_ROLE_KEY") { service_role_key },
        )
      end

      # Load or generate config
      config_file = Path.new(".env.config")
      if File.exists?(config_file)
        puts "Using existing config from #{config_file}" if @verbose
      else
        puts "Generating new config in #{config_file}" if @verbose
      end

      config = Dotenv.using(config_file) do |config_env|
        ConfigEnv.new(
          deployment_slot_name: config_env.generate("DEPLOYMENT_SLOT_NAME") { "Development" },
          deployment_slot_code: config_env.generate("DEPLOYMENT_SLOT_CODE") { "dev" },
          deployment_slot_port_offset: config_env.generate("DEPLOYMENT_SLOT_PORT_OFFSET") { "1" },
          # This needs to be replaced by the publicly available DNS name i.e. statbus.example.org
          statbus_url: config_env.generate("STATBUS_URL") { "http://localhost:3010" },
          # This needs to be replaced by the publicly available DNS name i.e. statbus-api.example.org
          browser_supabase_url: config_env.generate("BROWSER_SUPABASE_URL") { "http://localhost:3011" },
          # This is hardcoded for docker containers, as the name kong always resolves for the backend app.
          server_supabase_url: config_env.generate("SERVER_SUPABASE_URL") { "http://kong:8000" },
          seq_server_url: config_env.generate("SEQ_SERVER_URL") { "https://log.statbus.org" },
          # This must be provided and entered manually.
          seq_api_key: config_env.generate("SEQ_API_KEY") { "secret_seq_api_key" },
          # This must be provided and entered manually.
          slack_token: config_env.generate("SLACK_TOKEN") { "secret_slack_api_token" }
        )
      end

      # Calculate derived values
      base_port = 3000
      slot_multiplier = 10
      port_offset = base_port + (config.deployment_slot_port_offset.to_i * slot_multiplier)
      app_port = port_offset
      supabase_port = port_offset + 1

      derived = DerivedEnv.new(
        # The host address connected to the STATBUS app
        app_port: app_port,
        app_bind_address: "127.0.0.1:#{app_port}",
        # The host address connected to Supabase
        supabase_port: supabase_port,
        supabase_bind_address: "127.0.0.1:#{supabase_port}",
        # The publicly exposed address of PostgreSQL inside Supabase
        db_public_localhost_port: (port_offset + 2).to_s,
        # Git version of the deployed commit
        version: `git describe --always`.strip,
        # URL where the site is hosted
        site_url: config.statbus_url,
        # External URL for the API
        api_external_url: config.browser_supabase_url,
        # Public URL for Supabase access
        supabase_public_url: config.browser_supabase_url,
        # Caddy configuration
        deployment_user: "statbus_#{config.deployment_slot_code}",
        domain: "#{config.deployment_slot_code}.statbus.org",
        # Maps to GOTRUE_EXTERNAL_EMAIL_ENABLED to allow authentication with Email at all.
        # So SIGNUP really means SIGNIN
        enable_email_signup: true,
        # Allow creating users and setting the email as verified,
        # rather than sending an actual email where the user must
        # click the link.
        enable_email_autoconfirm: true,
        # Disables signup with EMAIL, when ENABLE_EMAIL_SIGNUP=true
        disable_signup: true,
        # Sets the project name in the Supabase API portal
        studio_default_project: config.deployment_slot_name
      )

      # Generate or update .env file
      new_content = generate_env_content(credentials, config, derived)
      if File.exists?(".env")
        puts "Checking existing .env for changes" if @verbose
        current_content = File.read(".env")

        if new_content != current_content
          backup_suffix = Time.utc.to_s("%Y-%m-%d")
          counter = 1
          while File.exists?(".env.backup.#{backup_suffix}")
            backup_suffix = "#{Time.utc.to_s("%Y-%m-%d")}_#{counter}"
            counter += 1
          end

          puts "Updating .env with changes - old version backed up as .env.backup.#{backup_suffix}" if @verbose
          File.write(".env.backup.#{backup_suffix}", current_content)
          File.write(".env", new_content)
        else
          puts "No changes detected in .env, skipping backup" if @verbose
        end
      else
        puts "Creating new .env file" if @verbose
        File.write(".env", new_content)
      end

      begin
        # Generate new Caddy content
        new_caddy_content = generate_caddy_content(derived)

        # Check if file exists and content differs
        deployment_caddyfilename = "deployment.caddyfile"
        if File.exists?(deployment_caddyfilename)
          current_content = File.read(deployment_caddyfilename)
          if new_caddy_content != current_content
            puts "Updating #{deployment_caddyfilename} with changes for #{derived.domain}" if @verbose
            File.write(deployment_caddyfilename, new_caddy_content)
          else
            puts "No changes needed in #{deployment_caddyfilename} for #{derived.domain}" if @verbose
          end
        else
          puts "Creating new #{deployment_caddyfilename} for #{derived.domain}" if @verbose
          File.write(deployment_caddyfilename, new_caddy_content)
        end
      end
    end
  end

  private def generate_env_content(credentials : CredentialsEnv, config : ConfigEnv, derived : DerivedEnv) : String
    content = <<-EOS
    ################################################################
    # Statbus Environment Variables
    # Generated by `#{PROGRAM_NAME} manage generate-config`
    # Used by docker compose, both for statbus containers
    # and for the included supabase containers.
    # The files:
    #   `.env.credentials` generated if missing, with stable credentials.
    #   `.env.config` generated if missing, configuration for installation.
    #   `.env` generated with input from `.env.credentials` and `.env.config`
    # The `.env` file contains settings used both by
    # the statbus app (Backend/frontend) and by the Supabase Docker
    # containers.
    #
    # The top level `docker-compose.yml` file includes all configuration
    # required for all statbus docker containers, but must be managed
    # by `./devops/manage-statbus.sh` that also sets the VERSION
    # required for precise logging by the statbus app.
    ################################################################

    ################################################################
    # Statbus Container Configuration
    ################################################################

    # The name displayed on the web
    DEPLOYMENT_SLOT_NAME=#{config.deployment_slot_name}
    # Urls configured in Caddy and DNS.
    STATBUS_URL=#{config.statbus_url}
    BROWSER_SUPABASE_URL=#{config.browser_supabase_url}
    SERVER_SUPABASE_URL=#{config.server_supabase_url}
    # Logging server
    SEQ_SERVER_URL=#{config.seq_server_url}
    SEQ_API_KEY=#{config.seq_api_key}
    # Deployment Messages
    SLACK_TOKEN=#{config.slack_token}
    # The prefix used for all container names in docker
    COMPOSE_INSTANCE_NAME=statbus-#{config.deployment_slot_code}
    # The host address connected to the STATBUS app
    APP_BIND_ADDRESS=#{derived.app_bind_address}
    # The host address connected to Supabase
    SUPABASE_BIND_ADDRESS=#{derived.supabase_bind_address}
    # The publicly exposed address of PostgreSQL inside Supabase
    DB_PUBLIC_LOCALHOST_PORT=#{derived.db_public_localhost_port}
    # Updated by manage-statbus.sh start required
    VERSION=#{derived.version}
    EOS
    content += "\n\n"

    supabase_env_filename = "supabase_docker/.env.example"
    content += <<-EOS
    ################################################################
    # Supabase Container Configuration
    # Adapted from #{supabase_env_filename}
    ################################################################
    EOS
    content += "\n\n"

    # Add Supabase Docker content with overrides
    supabase_env_path = Path.new(@project_directory, supabase_env_filename)
    supabase_env_content = File.read(supabase_env_path)
    content += Dotenv.using(supabase_env_content) do |env|
      # Override credentials
      env.set("POSTGRES_PASSWORD", credentials.postgres_password)
      env.set("JWT_SECRET", credentials.jwt_secret)
      env.set("ANON_KEY", credentials.anon_key)
      env.set("SERVICE_ROLE_KEY", credentials.service_role_key)
      env.set("DASHBOARD_USERNAME", credentials.dashboard_username)
      env.set("DASHBOARD_PASSWORD", credentials.dashboard_password)

      # Set derived values
      env.set("SITE_URL", derived.site_url)
      env.set("API_EXTERNAL_URL", derived.api_external_url)
      env.set("SUPABASE_PUBLIC_URL", derived.supabase_public_url)
      env.set("ENABLE_EMAIL_SIGNUP", derived.enable_email_signup.to_s)
      env.set("ENABLE_EMAIL_AUTOCONFIRM", derived.enable_email_autoconfirm.to_s)
      env.set("DISABLE_SIGNUP", derived.disable_signup.to_s)
      env.set("STUDIO_DEFAULT_PROJECT", derived.studio_default_project)

      # Return modified content without saving changes to example file
      env.dotenv_content.to_s
    end
    content += "\n\n"

    content += <<-EOS
    ################################################################
    # Statbus App Environment Variables
    # Next.js only exposes environment variables with the 'NEXT_PUBLIC_' prefix
    # to the browser cdoe.
    # Add all the variables here that are exposed publicly,
    # i.e. available in the web page source code for all to see.
    #
    NEXT_PUBLIC_SUPABASE_ANON_KEY=#{credentials.anon_key}
    NEXT_PUBLIC_BROWSER_SUPABASE_URL=#{config.browser_supabase_url}
    NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME=#{config.deployment_slot_name}
    NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE=#{config.deployment_slot_code}
    #
    ################################################################
    EOS

    return content
  end

  private def generate_caddy_content(derived : DerivedEnv) : String
    <<-EOS
    # Generated by #{PROGRAM_NAME} manage generate-config
    # Do not edit directly - changes will be lost
    #{derived.domain} {
            redir https://www.#{derived.domain}
    }

    www.#{derived.domain} {
            @maintenance {
                    file {
                            try_files /home/#{derived.deployment_user}/maintenance
                    }
            }
            handle @maintenance {
                    root * /home/#{derived.deployment_user}/statbus/app/public
                    rewrite * /maintenance.html
                    file_server {
                            status 503
                    }
            }
            reverse_proxy 127.0.0.1:#{derived.app_port}
    }

    api.#{derived.domain} {
            reverse_proxy 127.0.0.1:#{derived.supabase_port}
    }
    EOS
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

      if @verbose
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
        if @verbose
          STDOUT.puts "[empty - skipped]"
        end
        # Remove the migration record without running the file
        db.query_all(delete_sql, version, as: {version: String})
      else
        if @verbose
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
          if @debug && !output.empty?
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

          if @verbose
            STDOUT.puts "done (#{duration_ms}ms)"
            STDOUT.puts output if @debug && !output.empty?
          end
        else
          raise "Failed to roll back migration #{down_path}. Check the PostgreSQL logs for details."
        end
      end
    end
  end
end

StatBus.new
