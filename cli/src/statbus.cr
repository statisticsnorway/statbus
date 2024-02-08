require "http/client"
require "json"
require "time"
require "option_parser"
require "dir"
require "ini"
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
  # Mappings for a configuration, where every field is present.
  # Nil records the intention of not using an sql field
  # or not using a csv field.
  record ConfigFieldMapping, sql : String?, csv : String? do
    include JSON::Serializable
  end
  # Mapping for SQL where only sql fields that map to an actual csv
  record SqlFieldMapping, sql : String, csv : String do
    include JSON::Serializable
  end

  @mode = Mode::Welcome
  @import_mode : ImportMode | Nil = nil
  @manage_mode : ManageMode | Nil = nil
  @name = "statbus"
  @verbose = false
  @import_file_name : String | Nil = nil
  @config_field_mapping = Array(ConfigFieldMapping).new
  @config_file_path : Path | Nil = nil
  @sql_field_mapping = Array(SqlFieldMapping).new
  @working_directory = Dir.current
  @import_strategy = ImportStrategy::Copy
  @offset = 0

  def initialize
    option_parser = build_option_parser
    option_parser.parse
    run(option_parser)
  end

  def install
    puts "installing"
    # Download required files.
    Dir.cd("../supabase_docker") do
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
    # Find .env and load required secrets
    Dir.cd("../supabase_docker") do
      ini_data = File.read(".env")
      vars = INI.parse ini_data
      # The variables are all in the global scope, as an ".env" file is not really an ini file,
      # it just has the same
      global_vars = vars[""]
      postgres_host = "localhost"
      # global_vars["POSTGRES_HOST"]
      postgres_port = global_vars["DB_PUBLIC_LOCALHOST_PORT"]
      postgres_password = global_vars["POSTGRES_PASSWORD"]
      postgres_db = global_vars["POSTGRES_DB"]
      postgres_user = global_vars["POSTGRES_USER"]? || "postgres"
      #
      puts "Import data to postgres_port=#{postgres_port} postgres_password=#{postgres_password} postgres_password=#{postgres_password}" if @verbose
      puts "Loading data from #{import_file_name}"
      sql_field_required_list = ["tax_reg_ident"]
      sql_field_list = sql_field_required_list +
                       ["name",
                        "physical_region_code",
                        "primary_activity_category_code"]
      csv_stream = CSV.new(File.open(import_file_name), headers: true, separator: ',', quote_char: '"')
      csv_fields_list = csv_stream.headers
      # For every equal header, insert a mapping.
      sql_field_required = sql_field_required_list.to_set
      puts "sql_field_required #{sql_field_required}" if @verbose
      sql_field = sql_field_list.to_set
      puts "sql_field #{sql_field}" if @verbose
      csv_fields = csv_fields_list.to_set
      puts "csv_fields #{csv_fields}" if @verbose
      common_fields = sql_field & csv_fields
      puts "common_fields #{common_fields}" if @verbose
      common_fields.each do |common_field|
        @sql_field_mapping.push(SqlFieldMapping.new(sql: common_field, csv: common_field))
      end
      puts "@config_field_mapping #{@config_field_mapping}" if @verbose
      puts "@sql_field_mapping #{@sql_field_mapping}" if @verbose
      @config_field_mapping.each do |mapping|
        if !(mapping.csv.nil? || mapping.sql.nil?)
          @sql_field_mapping.push(SqlFieldMapping.new(sql: mapping.sql.not_nil!, csv: mapping.csv.not_nil!))
        end
      end
      puts "@sql_field_mapping #{@sql_field_mapping}" if @verbose
      mapped_sql_field = @sql_field_mapping.map(&.sql).to_set
      mapped_csv_field = @config_field_mapping.map(&.csv).to_set
      puts "mapped_sql_field #{mapped_sql_field}" if @verbose
      puts "mapped_csv_field #{mapped_csv_field}" if @verbose
      missing_required_sql_fields = sql_field_required - mapped_sql_field

      config_sql_field = @config_field_mapping.map(&.sql).compact.to_set - mapped_sql_field
      config_csv_field = @config_field_mapping.map(&.csv).compact.to_set - mapped_csv_field
      # Check the fields
      missing_config_sql_fields = sql_field - config_sql_field - mapped_sql_field

      if missing_required_sql_fields.any? || missing_config_sql_fields.any?
        # Build the empty mappings for displaying a starting point to the user:
        # For every absent header, insert an absent mapping.
        sql_missing_fields = sql_field - mapped_sql_field
        sql_missing_fields.each do |sql_field|
          @config_field_mapping.push(ConfigFieldMapping.new(sql: sql_field, csv: "?"))
        end
        csv_missing_fields = csv_fields - mapped_csv_field
        csv_missing_fields.each do |csv_field|
          @config_field_mapping.push(ConfigFieldMapping.new(sql: "?", csv: csv_field))
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

        raise ArgumentError.new("Missing sql fields #{sql_missing_fields.to_a.to_pretty_json} you need to add a mapping")
      end

      puts "@sql_field_mapping = #{@sql_field_mapping}" if @verbose
      puts "@config_field_mapping = #{@config_field_mapping}" if @verbose
      # Sort header mappings based on position in sql_field_list
      @sql_field_mapping.sort_by! do |mapping|
        # Every field found is order according to its position
        {1, sql_field_list.index(mapping.sql).not_nil!, ""}
      end

      Dir.cd(@working_directory) do
        if !@config_file_path.nil?
          if !File.exists?(@config_file_path.not_nil!)
            puts "Writing file #{@config_file_path}"
            File.write(
              @config_file_path.not_nil!,
              @sql_field_mapping.to_pretty_json
            )
            puts @sql_field_mapping.to_pretty_json
          end
        end
      end

      DB.connect("postgres://#{postgres_user}:#{postgres_password}@#{postgres_host}:#{postgres_port}/#{postgres_db}") do |db|
        sql_fields_str = @sql_field_mapping.map do |mapping|
          if !mapping.sql.nil?
            db.escape_identifier(mapping.sql.not_nil!)
          end
        end.compact.join(",")
        puts "sql_fields_str = #{sql_fields_str}" if @verbose

        case @import_strategy
        when ImportStrategy::Copy
          copy_stream = db.exec_copy "COPY public.legal_unit_region_activity_category_current(#{sql_fields_str}) FROM STDIN"
          iterate_csv_stream(csv_stream) do |sql_row, csv_row|
            sql_row.any? do |value|
              if !value.nil? && value.includes?("\t")
                raise ArgumentError.new("Found illegal character TAB \\t in row #{csv_row}")
              end
            end
            sql_text = sql_row.join("\t")
            puts "Uploading #{sql_text}" if @verbose
            copy_stream.puts sql_text
          end
          puts "Waiting for processing" if @verbose
          copy_stream.close
          db.close
        when ImportStrategy::Insert
          sql_args = (1..(@sql_field_mapping.size)).map { |i| "$#{i}" }.join(",")
          sql_statment = "INSERT INTO public.legal_unit_region_activity_category_current(#{sql_fields_str}) VALUES(#{sql_args})"
          puts "sql_statment = #{sql_statment}" if @verbose
          db.exec "BEGIN;"
          # Set a config that prevents inner trigger functions form activating constraints,
          # make the deferral moot.
          db.exec "SET LOCAL statbus.constraints_already_deferred TO 'true';"
          db.exec "SET CONSTRAINTS ALL DEFERRED;"
          insert = db.build sql_statment
          batch_size = 10000
          batch_item = 0
          iterate_csv_stream(csv_stream) do |sql_row, csv_row|
            batch_item += 1
            puts "Uploading #{sql_row}" if @verbose
            insert.exec(args: sql_row)
            if (batch_item % batch_size) == 0
              puts "Commit-ing changes and refreshing statistical_unit"
              db.exec "END;"
              db.exec "SET CONSTRAINTS ALL IMMEDIATE;"
              db.exec "SELECT statistical_unit_refresh_now();"
              db.exec "BEGIN;"
              db.exec "SET LOCAL statbus.constraints_already_deferred TO 'true';"
              db.exec "SET CONSTRAINTS ALL DEFERRED;"
              insert = db.build sql_statment
            end
          end
          db.exec "SET CONSTRAINTS ALL IMMEDIATE;"
          db.exec "END;"
          db.exec "SELECT statistical_unit_refresh_now();"
          db.close
        end
      end
    end
  end

  private def iterate_csv_stream(csv_stream)
    rowcount = 0
    while csv_stream.next
      rowcount += 1
      if 0 < @offset
        if rowcount < @offset
          next
        elsif rowcount == @offset
          puts "Continuing after  #{rowcount.format(delimiter: '_')} rows"
          next
        end
      end
      csv_row = csv_stream.row
      sql_row = @sql_field_mapping.map do |mapping|
        csv_value = csv_row[mapping.csv]
        if csv_value.nil?
          nil
        else
          csv_value.strip
        end
      end
      yield(sql_row, csv_row)
      if (rowcount % 1000) == 0
        puts "Uploaded #{rowcount.format(delimiter: '_')} rows"
      end
    end
    puts "Wrote #{rowcount} rows"
  end

  private def build_option_parser
    OptionParser.new do |parser|
      parser.banner = "Usage: #{@name} [subcommand] [arguments]"
      parser.on("install", "Install StatBus") do
        @mode = Mode::Install
        parser.banner = "Usage: #{@name} install [arguments]"
        parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |name| @name = name }
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
        parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |name| @name = name }
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
        parser.on("-c FILENAME", "--config=FILENAME", "A config file with field mappings. Will be written to with an example if the file does not exist.") do |file_name|
          Dir.cd(@working_directory) do
            @config_file_path = Path.new(file_name)
            if File.exists?(@config_file_path.not_nil!)
              config_data = File.read(@config_file_path.not_nil!)
              @config_field_mapping = Array(ConfigFieldMapping).from_json(config_data)
            else
              STDERR.puts "Could not find #{@config_file_path}"
            end
          end
        end
        parser.on("-m NEW=OLD", "--mapping=NEW=OLD", "A field name mapping") do |mapping|
          sql, csv = mapping.split("=").map do |field_name|
            if field_name.empty? || field_name == "nil"
              nil
            else
              field_name
            end
          end
          @config_field_mapping.push(ConfigFieldMapping.new(sql: sql, csv: csv))
        end
      end
      parser.on("welcome", "Print a greeting message") do
        @mode = Mode::Welcome
        parser.banner = "Usage: #{@name} welcome"
      end
      parser.on("-v", "--verbose", "Enabled verbose output") { @verbose = true }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
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
      case @import_mode
      when ImportMode::LegalUnit
        if @import_file_name.nil?
          STDERR.puts "missing required name of file to read from"
          # puts parser
        else
          import_legal_units(@import_file_name.not_nil!)
        end
      when ImportMode::Establishment
        puts "Importing establishments"
      else
        puts "Unknown import mode #{@import_mode}"
        # puts parser
        exit(1)
      end
    when Nil
      # puts parser
    else
      puts "Unknown mode #{@mode}"
      exit(1)
    end
  end
end

StatBus.new
