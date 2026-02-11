require "http/client"
require "json"
require "digest/sha256"
require "time"
require "option_parser"
require "dir"
require "pg"
require "file"
require "csv"
require "yaml"
require "jwt"
require "./dotenv"
require "./config"
require "./migrate"
require "./import"
require "./manage"
require "./worker"

module Statbus
  # Compatibility helper for Time.instant (Crystal 1.19+) vs Time.monotonic (older)
  # Time.monotonic was deprecated in favor of Time.instant in Crystal 1.19.0
  macro monotonic_time
    {% if compare_versions(Crystal::VERSION, "1.19.0") >= 0 %}
      Time.instant
    {% else %}
      Time.monotonic
    {% end %}
  end
  class Cli
    enum Mode
      Manage
      Import
      Migrate
      Worker
    end

    @name = "statbus"
    @mode : Mode | Nil = nil

    def initialize
      @config = Config.new
      @migrate = Migrate.new(@config)
      @import = Import.new(@config)
      @manage = Manage.new(@config)
      @worker = Worker.new(@config)
      begin
        option_parser = build_option_parser
        option_parser.parse

        # Log the final debug settings after command line parsing
        if @config.debug
          puts "Final debug settings after command line parsing:"
          puts "  verbose=#{@config.verbose}"
          puts "  debug=#{@config.debug}"
        end

        run(option_parser)
      rescue ex : ArgumentError
        puts ex
        exit 1
      end
    end

    private def build_option_parser
      OptionParser.new do |parser|
        parser.banner = "Usage: #{@name} [subcommand] [arguments]"
        parser.on("-v", "--verbose", "Enable verbose output") { @config.verbose = true }
        parser.on("-d", "--debug", "Enable debug output") { @config.debug = true }
        parser.on("-q", "--quiet", "Disable verbose output (overrides VERBOSE env var)") { @config.verbose = false }
        parser.on("-h", "--help", "Show help, available for subcommands") do
          puts parser
          exit
        end
        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts parser
          exit(1)
        end
        parser.on("manage", "Manage installed StatBus") do
          @mode = Mode::Manage
          parser.banner = "Usage: #{@name} manage [arguments]"
          parser.on("install", "Install StatBus") do
            @manage.mode = Manage::Mode::Install
            parser.banner = "Usage: #{@name} install [arguments]"
          end
          parser.on("start", "Start StatBus with docker compose") do
            @manage.mode = Manage::Mode::Start
          end
          parser.on("stop", "Stop StatBus with docker compose") do
            @manage.mode = Manage::Mode::Stop
          end
          parser.on("status", "Status on StatBus") do
            @manage.mode = Manage::Mode::Status
          end
          parser.on("create-users", "Create users from .users.yml file") do
            @manage.mode = Manage::Mode::CreateUsers
          end
          parser.on("generate-config", "Generate configuration files") do
            @manage.mode = Manage::Mode::GenerateConfig
          end
        end
        parser.on("worker", "Run Statbus Worker for background processing") do
          @mode = Mode::Worker
          parser.on("--stop-when-idle", "Exit when all queues are idle (for testing)") do
            @worker.stop_when_idle = true
          end
          parser.on("--database DB", "Override database name") do |db|
            @config.postgres_db = db
          end
        end
        parser.on("import", "Import into installed StatBus") do
          @mode = Mode::Import
          parser.banner = "Usage: #{@name} import [legal_unit|establishment] [arguments]"
          parser.on("legal_unit", "Import legal units") do
            parser.banner = "Usage: #{@name} import legal_unit [arguments]"
            @import.mode = Import::Mode::LegalUnit
          end
          parser.on("establishment", "Import legal units") do
            parser.banner = "Usage: #{@name} import establishment [arguments]"
            @import.mode = Import::Mode::Establishment
          end
          parser.on("-f FILENAME", "--file=FILENAME", "The file to read from") do |file_name|
            import_file_name = file_name
            @import.import_file_name = import_file_name
            puts "Loading data from #{@import.import_file_name}"
          end
          parser.on("-o offset", "--offset=NUMBER", "Number of rows to skip") do |offset|
            @import.offset = offset.to_i(underscore: true)
          end
          parser.on("-s STRATEGY", "--strategy=STRATEGY", "Use fast bulk \"copy\" or slower \"insert\" with earlier error messages.") do |strategy|
            case strategy
            when "copy"
              @import.import_strategy = Import::Strategy::Copy
            when "insert"
              @import.import_strategy = Import::Strategy::Insert
            else
              puts "Unknown strategy: use COPY or INSERT"
              puts parser
              exit(1)
            end
          end
          parser.on("-t path.for.tag", "--tag=path.for.tag", "Insert scoped to a tag - limits valid_to, valid_from and adds the tag") do |tag|
            @import.import_tag = tag
          end
          parser.on("-c FILENAME", "--config=FILENAME", "A config file with field mappings. Will be written to with an example if the file does not exist.") do |file_name|
            Dir.cd(@config.working_directory) do
              @import.config_field_mapping_file_path = Path.new(file_name)
              if File.exists?(@import.config_field_mapping_file_path.not_nil!)
                puts "Loading mapping from #{file_name}"
                config_data = File.read(@import.config_field_mapping_file_path.not_nil!)
                @import.config_field_mapping = Array(Import::ConfigFieldMapping).from_json(config_data)
              else
                STDERR.puts "Could not find #{@import.config_field_mapping_file_path}"
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
            @import.config_field_mapping.push(Import::ConfigFieldMapping.new(sql: sql, csv: csv))
          end
          parser.on("--immediate-constraint-checking", "Check constraints for each record immediately") do
            @delayed_constraint_checking = false
          end
          parser.on("-u EMAIL", "--user=EMAIL", "Email of the user performing the import") do |user_email|
            @import.user_email = user_email
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
            parser.on("one", "Run one up migration (The default is all)") do
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
            parser.on("all", "Run all down migrations (The default is one)") do
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
      in Mode::Manage
        @manage.run(option_parser)
      in Mode::Worker
        # When running as a worker, use the config's verbose and debug settings
        puts "Starting worker with verbose=#{@config.verbose}, debug=#{@config.debug}" if @config.verbose
        @worker.run
      in Mode::Import
        @import.run(option_parser)
      in Mode::Migrate
        @migrate.run(option_parser)
      in nil
        puts "StatBus is a locally installable STATistical BUSiness registry"
        puts option_parser
      end
    end
  end
end
