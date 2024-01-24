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

# TODO: Write documentation for `Statbus`
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

mode : Mode | Nil = nil
import_mode : ImportMode | Nil = nil
manage_mode : ManageMode | Nil = nil
name = "statbus"
verbose = false
import_filename : String | Nil = nil

parser = OptionParser.new do |parser|
  parser.banner = "Usage: #{name} [subcommand] [arguments]"
  parser.on("install", "Install StatBus") do
    mode = Mode::Install
    parser.banner = "Usage: #{name} install [arguments]"
    parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |_name| name = _name }
  end
  parser.on("manage", "Manage installed StatBus") do
    mode = Mode::Manage
    parser.banner = "Usage: #{name} manage [arguments]"
    parser.on("start", "Start StatBus with docker compose") do
      manage_mode = ManageMode::Start
    end
    parser.on("stop", "Stop StatBus with docker compose") do
      manage_mode = ManageMode::Stop
    end
    parser.on("status", "Status on StatBus") do
      manage_mode = ManageMode::Status
    end
    parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |_name| name = _name }
  end
  parser.on("import", "Import into installed StatBus") do
    mode = Mode::Import
    parser.banner = "Usage: #{name} import [legal_unit|establishment] [arguments]"
    parser.on("legal_unit", "Import legal units") do
      parser.banner = "Usage: #{name} import legal_unit [arguments]"
      import_mode = ImportMode::LegalUnit
    end
    parser.on("establishment", "Import legal units") do
      parser.banner = "Usage: #{name} import establishment [arguments]"
      import_mode = ImportMode::Establishment
    end
    parser.on("-f NAME", "--file=NAME", "The file to read from") { |_name| import_filename = _name }
  end
  parser.on("welcome", "Print a greeting message") do
    mode = Mode::Welcome
    parser.banner = "Usage: #{name} welcome"
  end
  parser.on("-v", "--verbose", "Enabled verbose output") { verbose = true }
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
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

def import_legal_units(import_filename : String)
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
    puts "Import data to postgres_port=#{postgres_port} postgres_password=#{postgres_password} postgres_password=#{postgres_password}"
    puts "Loading data from #{import_filename}"
    DB.connect("postgres://#{postgres_user}:#{postgres_password}@#{postgres_host}:#{postgres_port}/#{postgres_db}") do |db|
      copy = db.exec_copy "COPY public.legal_unit_region_activity_category_stats_current(tax_reg_ident,name,employees,physical_region_code,primary_activity_category_code) FROM STDIN"
      csv = CSV.new(File.open(import_filename), headers: true, separator: ',', quote_char: '"')
      while csv.next
        sql_text = [csv["tax_reg_ident"],
                    csv["name"],
                    csv["employees"],
                    csv["physical_region_code"],
                    csv["primary_activity_category_code"],
        ].map do |v|
          case v
          when nil then nil
          when ""  then nil
          else          v
          end
        end.join("\t")
        puts "Uploading #{sql_text}"
        copy.puts sql_text
      end
      puts "Waiting for processing"
      copy.close
      db.close
    end
  end
end

parser.parse
case mode
when Mode::Welcome
  puts "StatBus is a locally installable STATistical BUSiness registry"
when Mode::Install
  install
when Mode::Manage
  case manage_mode
  when ManageMode::Start
    manage_start
  when ManageMode::Stop
    manage_stop
  when ManageMode::Status
    manage_status
  else
    puts "Unknown manage mode #{manage_mode}"
    puts parser
    exit(1)
  end
when Mode::Import
  case import_mode
  when ImportMode::LegalUnit
    if import_filename.nil?
      STDERR.puts "missing required name of file to read from"
      puts parser
    else
      import_legal_units(import_filename.as(String))
    end
  when ImportMode::Establishment
    puts "Importing establishments"
  else
    puts "Unknown import mode #{import_mode}"
    puts parser
    exit(1)
  end
  STDERR.puts "legal_unit or establishment?" if verbose
when Nil
  puts parser
else
  puts "Unknown mode #{mode}"
  exit(1)
end
