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
require "./import"

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
    enum ManageMode
      Start
      Stop
      Status
      CreateUsers
      GenerateConfig
    end

    @name = "statbus"
    @mode : Mode | Nil = nil
    @manage_mode : ManageMode | Nil = nil

    def initialize
      @config = Config.new
      @migrate = Migrate.new(@config)
      @import = Import.new(@config)
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
          parser.on("--skip-refresh-of-materialized-views", "Avoid refreshing materialized views during and after load") do
            @refresh_materialized_views = false
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
        @import.run(option_parser)
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
