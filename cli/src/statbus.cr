require "http/client"
require "json"
require "digest/sha256"
require "time"
require "option_parser"
require "dir"
require "db"
require "pg"
require "file"
require "csv"
require "yaml"
require "jwt"
require "./dotenv"
require "./config"
require "./migrate"

# The `Statbus` module is designed to manage and import data for a statistical business registry.
# It supports various operations like installation, management (start, stop, status), and data import.
module Statbus
  class Cli
    enum Mode
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
    # Mappings for a configuration, where every field is present.
    # Nil records the intention of not using an sql field
    # or not using a csv field.
    record ConfigFieldMapping, sql : String?, csv : String? do
      include JSON::Serializable
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

    @mode : Mode | Nil = nil
    @import_mode : ImportMode | Nil = nil
    @manage_mode : ManageMode | Nil = nil
    @name = "statbus"
    @delayed_constraint_checking = true
    @refresh_materialized_views = true
    @import_file_name : String | Nil = nil
    @config_field_mapping = Array(ConfigFieldMapping).new
    @config_field_mapping_file_path : Path | Nil = nil
    @sql_field_mapping = Array(SqlFieldMapping).new

    @import_strategy = ImportStrategy::Copy
    @import_tag : String | Nil = nil
    @offset = 0
    @valid_from : String = Time.utc.to_s("%Y-%m-%d")
    @valid_to = "infinity"
    @user_email : String | Nil = nil

    def initialize
      @config = Config.new
      @migrate = Migrate.new(@config)
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
      Dir.cd(@config.project_directory) do
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
      config = Config.new
      Dir.cd(@config.project_directory) do
        puts "Import data to #{config.connection_string}" if @verbose

        sql_cli_provided_fields = ["valid_from", "valid_to", "tag_path"]
        sql_fields_list = sql_cli_provided_fields + sql_field_required_list + sql_field_optional_list
        file_stream =
          Dir.cd(@config.working_directory) do
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
          Dir.cd(@config.working_directory) do
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

        Dir.cd(@config.working_directory) do
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

    private def iterate_csv_stream(csv_stream, &)
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
        parser.on("-h", "--help", "Show help, available for subcommands") do
          puts parser
          exit
        end
        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts parser
          exit(1)
        end
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
            Dir.cd(@config.working_directory) do
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
            @migrate.mode = Migrate::Mode::Up
            @migrate.migrate_all = true
            parser.on("--to VERSION", "Migrate up to specific version") do |version|
              @migrate.migrate_to = version.to_i64
            end
            parser.on("one", "Run one up migration") do
              @migrate.migrate_all = false
            end
          end
          parser.on("new", "Create a new migration file") do
            @migrate.mode = Migrate::Mode::New
            parser.on("-d DESC", "--description=DESC", "Description for the migration") do |desc|
              @migrate.migration_minor_description = desc
            end
            parser.on("-e EXT", "--extension=EXT", "File extension for the migration (sql or psql, defaults to sql)") do |ext|
              if ext != "sql" && ext != "psql"
                STDERR.puts "Error: Extension must be 'sql' or 'psql'"
                exit(1)
              end
              @migrate.migration_extension = ext
            end
          end
          parser.on("down", "Roll back migrations") do
            @migrate.mode = Migrate::Mode::Down
            @migrate.migrate_all = false
            parser.on("--to VERSION", "Roll back to specific version") do |version|
              @migrate.migrate_to = version.to_i64
            end
            parser.on("all", "Run all down migrations") do
              @migrate.migrate_all = true
            end
          end
          parser.on("redo", "Roll back last migration and reapply it") do
            @migrate.mode = Migrate::Mode::Redo
          end
          parser.on("convert", "Convert existing migrations to timestamp format") do
            @migrate.mode = Migrate::Mode::Convert
            parser.on("--start=DATE", "Start date for conversion (default: 2024-01-01)") do |date|
              @migrate.convert_start_date = Time.parse(date, "%Y-%m-%d", Time::Location::UTC)
            end
            parser.on("--spacing=DAYS", "Days between migrations (default: 1)") do |days|
              @migrate.convert_spacing = days.to_i.days
            end
          end
        end
      end
    end

    private def run(option_parser : OptionParser)
      case @mode
      in Mode::Install
        install
      in Mode::Manage
        case @manage_mode
        in ManageMode::Start
          manage_start
        in ManageMode::Stop
          manage_stop
        in ManageMode::Status
          manage_status
        in ManageMode::CreateUsers
          create_users
        in ManageMode::GenerateConfig
          manage_generate_config
        in nil
          puts option_parser
          exit(1)
        end
      in Mode::Import
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
          in ImportMode::LegalUnit
            import_legal_units(@import_file_name.not_nil!)
          in ImportMode::Establishment
            import_establishments(@import_file_name.not_nil!)
          in nil
            puts option_parser
            exit(1)
          end
        end
      in Mode::Migrate
        @migrate.run(option_parser)
      in nil
        puts "StatBus is a locally installable STATistical BUSiness registry"
        puts option_parser
      end
    end

    private def create_users
      config = Config.new

      Dir.cd(@config.project_directory) do
        if !File.exists?(".users.yml")
          STDERR.puts "Error: .users.yml file not found"
          exit(1)
        end

        DB.connect(config.connection_string) do |db|
          available_roles : Array(String) = ["super_user", "regular_user", "restricted_user", "external_user"]
          begin
            Dir.cd(@config.project_directory) do
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
      Dir.cd(@config.project_directory) do
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
      supabase_env_path = Path.new(@config.project_directory, supabase_env_filename)
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
  end
end

Statbus::Cli.new
