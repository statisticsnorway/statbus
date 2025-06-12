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
require "ecr"
require "./dotenv"
require "./config"

module Statbus
  class Manage
    enum Mode
      Install
      Start
      Stop
      Status
      CreateUsers
      GenerateConfig
    end

    property mode : Mode | Nil = nil
    property config : Config

    def initialize(config)
      @config = config
    end

    def run(option_parser : OptionParser)
      case @mode
      in Mode::Install
        install
      in Mode::Start
        manage_start
      in Mode::Stop
        manage_stop
      in Mode::Status
        manage_status
      in Mode::CreateUsers
        create_users
      in Mode::GenerateConfig
        manage_generate_config
      in nil
        puts option_parser
        exit(1)
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

    private def create_users
      config = Config.new

      Dir.cd(@config.project_directory) do
        if !File.exists?(".users.yml")
          STDERR.puts "Error: .users.yml file not found"
          exit(1)
        end

        DB.connect(config.connection_string) do |db|
          available_roles : Array(String) = ["admin_user", "regular_user", "restricted_user", "external_user"]
          begin
            Dir.cd(@config.project_directory) do
              available_roles = db.query_all(
                "SELECT unnest(enum_range(NULL::public.statbus_role))::text AS role",
                as: {role: String}
              ).map { |r| r[:role] }
            end
          rescue ex
            STDERR.puts "Warning: Could not load roles from database: #{ex.message}"
          end

          # Read users from YAML file
          users_yaml = File.read(".users.yml")
          users = YAML.parse(users_yaml)

          users.as_a.each do |user|
            email = user["email"].as_s
            password = user["password"].as_s
            # Default to regular_user if role not specified
            role = user["role"]?.try(&.as_s) || "regular_user"
            # Gracefully change from old name to new name, to avoid too many changes.
            if role == "super_user"
              role = "admin_user"
            end

            # Validate role
            if !available_roles.includes?(role)
              STDERR.puts "Error: Invalid role '#{role}' for user #{email}"
              STDERR.puts "Available roles: #{available_roles.join(", ")}"
              exit(1)
            end

            puts "Creating user: #{email} with role: #{role}" if @config.verbose

            db.exec(
              "SELECT * FROM public.user_create($1, $2, $3)",
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
      postgres_admin_password : String,
      postgres_app_password : String,
      postgres_authenticator_password : String,
      jwt_secret : String,
      dashboard_username : String,
      dashboard_password : String,
      service_role_key : String

    # Type-safe configuration structure
    record ConfigEnv,
      deployment_slot_name : String,
      deployment_slot_code : String,
      deployment_slot_port_offset : String,
      statbus_url : String,
      browser_api_url : String,
      server_api_url : String,
      seq_server_url : String,
      seq_api_key : String,
      slack_token : String,
      postgres_admin_db : String,
      postgres_admin_user : String,
      postgres_app_db : String,
      postgres_app_user : String,
      access_jwt_expiry : String,
      refresh_jwt_expiry : String,
      caddy_deployment_mode : String,
      site_domain : String,
      debug : String,
      next_public_debug : String

    # Configuration values that are derived from other settings
    record DerivedEnv,
      caddy_http_port : Int32,
      caddy_http_bind_address : String,
      caddy_https_port : Int32,
      caddy_https_bind_address : String,
      app_port : Int32,
      app_bind_address : String,
      postgrest_port : Int32,
      postgrest_bind_address : String,
      db_public_localhost_port : Int32,
      version : String,
      site_url : String,
      api_external_url : String,
      api_public_url : String,
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
          puts "Using existing credentials from #{credentials_file}" if @config.verbose
        else
          puts "Generating new credentials in #{credentials_file}" if @config.verbose
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

          service_role_key = JWT.encode(service_role_payload, jwt_secret, JWT::Algorithm::HS256)

          CredentialsEnv.new(
            postgres_admin_password: credentials_env.generate("POSTGRES_ADMIN_PASSWORD") { random_string(20) },
            postgres_app_password: credentials_env.generate("POSTGRES_APP_PASSWORD") { random_string(20) },
            postgres_authenticator_password: credentials_env.generate("POSTGRES_AUTHENTICATOR_PASSWORD") { random_string(20) },
            jwt_secret: jwt_secret,
            dashboard_username: credentials_env.generate("DASHBOARD_USERNAME") { "admin" },
            dashboard_password: credentials_env.generate("DASHBOARD_PASSWORD") { random_string(20) },
            service_role_key: credentials_env.generate("SERVICE_ROLE_KEY") { service_role_key },
          )
        end

        # Load or generate config
        config_file = Path.new(".env.config")
        if File.exists?(config_file)
          puts "Using existing config from #{config_file}" if @config.verbose
        else
          puts "Generating new config in #{config_file}" if @config.verbose
        end

        config = Dotenv.using(config_file) do |config_env|
          deployment_slot_code = config_env.generate("DEPLOYMENT_SLOT_CODE") { "dev" }
          postgres_app_db = config_env.generate("POSTGRES_APP_DB") { "statbus_#{deployment_slot_code}" }
          postgres_app_user = config_env.generate("POSTGRES_APP_USER") { "statbus_#{deployment_slot_code}" }
          ConfigEnv.new(
            deployment_slot_name: deployment_slot_code,
            deployment_slot_code: config_env.generate("DEPLOYMENT_SLOT_CODE") { "dev" },
            deployment_slot_port_offset: config_env.generate("DEPLOYMENT_SLOT_PORT_OFFSET") { "1" },
            # This needs to be replaced by the publicly available DNS name i.e. statbus.example.org
            statbus_url: config_env.generate("STATBUS_URL") { "http://localhost:3010" },
            # This needs to be replaced by the publicly available DNS name i.e. statbus-api.example.org
            browser_api_url: config_env.generate("BROWSER_REST_URL") { "http://localhost:3011" },
            # This is hardcoded for docker containers, as the name proxy always resolves for the backend app.
            server_api_url: config_env.generate("SERVER_REST_URL") { "http://proxy:80" },
            seq_server_url: config_env.generate("SEQ_SERVER_URL") { "https://log.statbus.org" },
            # This must be provided and entered manually.
            seq_api_key: config_env.generate("SEQ_API_KEY") { "secret_seq_api_key" },
            # This must be provided and entered manually.
            slack_token: config_env.generate("SLACK_TOKEN") { "secret_slack_api_token" },
            # Database configuration
            postgres_admin_db: config_env.generate("POSTGRES_ADMIN_DB") { "postgres" },
            postgres_admin_user: config_env.generate("POSTGRES_ADMIN_USER") { "postgres" },
            postgres_app_db: postgres_app_db,
            postgres_app_user: postgres_app_user,
            # JWT configuration
            access_jwt_expiry: config_env.generate("ACCESS_JWT_EXPIRY") { "3600" }, # 1 hour in seconds
            refresh_jwt_expiry: config_env.generate("REFRESH_JWT_EXPIRY") { "2592000" }, # 30 days in seconds
            # Caddy configuration
            caddy_deployment_mode: config_env.generate("CADDY_DEPLOYMENT_MODE") { "development" },
            site_domain: config_env.generate("SITE_DOMAIN") { "#{deployment_slot_code}.statbus.org" },
            # Debug flags
            debug: config_env.generate("DEBUG") { "false" },
            next_public_debug: config_env.generate("NEXT_PUBLIC_DEBUG") { "false" }
          )
        end

        # Calculate derived values
        base_port = 3000
        slot_multiplier = 10
        port_offset = base_port + (config.deployment_slot_port_offset.to_i * slot_multiplier)
        caddy_http_port = port_offset
        caddy_https_port = port_offset + 1
        app_port = port_offset + 2
        postgrest_port = port_offset + 3
        db_public_localhost_port = port_offset + 4
        
        if config.caddy_deployment_mode == "standalone"
          # For standalone mode, bind to all interfaces, at the official HTTP(S) ports.
          caddy_http_port = 80
          caddy_https_port = 443
          caddy_http_bind_address = "0.0.0.0:#{caddy_http_port}"
          caddy_https_bind_address = "0.0.0.0:#{caddy_https_port}"
        else
          # For other modes, bind to localhost with non conflicting ports for running multiple statbus installations on the same host.
          caddy_http_bind_address = "127.0.0.1:#{caddy_http_port}"
          caddy_https_bind_address = "127.0.0.1:#{caddy_https_port}"
        end

        derived = DerivedEnv.new(
          # Caddy
          caddy_http_port: caddy_http_port,
          caddy_https_port: caddy_https_port,
          caddy_http_bind_address: caddy_http_bind_address,
          caddy_https_bind_address: caddy_https_bind_address,
          # The host address connected to the STATBUS app
          app_port: app_port,
          app_bind_address: "127.0.0.1:#{app_port}",
          # The host address connected to Supabase
          postgrest_port: postgrest_port,
          postgrest_bind_address: "127.0.0.1:#{postgrest_port}",
          # The publicly exposed address of PostgreSQL inside Supabase
          db_public_localhost_port: db_public_localhost_port,
          # Git version of the deployed commit
          version: `git describe --always`.strip,
          # URL where the site is hosted
          site_url: config.statbus_url,
          # External URL for the API
          api_external_url: config.browser_api_url,
          # Public URL for Supabase access
          api_public_url: config.browser_api_url,
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
          puts "Checking existing .env for changes" if @config.verbose
          current_content = File.read(".env")

          if new_content != current_content
            backup_suffix = Time.utc.to_s("%Y-%m-%d")
            counter = 1
            while File.exists?(".env.backup.#{backup_suffix}")
              backup_suffix = "#{Time.utc.to_s("%Y-%m-%d")}_#{counter}"
              counter += 1
            end

            puts "Updating .env with changes - old version backed up as .env.backup.#{backup_suffix}" if @config.verbose
            File.write(".env.backup.#{backup_suffix}", current_content)
            File.write(".env", new_content)
          else
            puts "No changes detected in .env, skipping backup" if @config.verbose
          end
        else
          puts "Creating new .env file" if @config.verbose
          File.write(".env", new_content)
        end

        # Generate and write all Caddyfile variants
        generate_caddy_content(derived, config)
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
    DEPLOYMENT_SLOT_CODE=#{config.deployment_slot_code}
    # Urls configured in Caddy and DNS.
    STATBUS_URL=#{config.statbus_url}
    BROWSER_REST_URL=#{config.browser_api_url}
    SERVER_REST_URL=#{config.server_api_url}
    # Logging server
    SEQ_SERVER_URL=#{config.seq_server_url}
    SEQ_API_KEY=#{config.seq_api_key}
    # Deployment Messages
    SLACK_TOKEN=#{config.slack_token}
    # The prefix used for all container names in docker
    COMPOSE_INSTANCE_NAME=statbus-#{config.deployment_slot_code}
    # Caddy configuration
    CADDY_HTTP_PORT=#{derived.caddy_http_port}
    CADDY_HTTPS_PORT=#{derived.caddy_https_port}
    CADDY_HTTP_BIND_ADDRESS=#{derived.caddy_http_bind_address}
    CADDY_HTTPS_BIND_ADDRESS=#{derived.caddy_https_bind_address}
    # The host address connected to the STATBUS app
    APP_BIND_ADDRESS=#{derived.app_bind_address}
    # The host address connected to Supabase
    REST_BIND_ADDRESS=#{derived.postgrest_bind_address}
    # The publicly exposed address of PostgreSQL inside Supabase
    DB_PUBLIC_LOCALHOST_PORT=#{derived.db_public_localhost_port}
    # Updated by manage-statbus.sh start required
    VERSION=#{derived.version}

    # Server-side debugging for the Statbus App. Requires app restart.
    # To enable, edit .env: set DEBUG=true and comment out/remove DEBUG=false.
    # To disable, edit .env: set DEBUG=false and comment out/remove DEBUG=true.
    # This setting is sourced from DEBUG in .env.config (defaults to false).
    #{
      if config.debug == "true"
        "DEBUG=true\n#DEBUG=false"
      else
        "#DEBUG=true\nDEBUG=false"
      end
    }
    EOS
      content += "\n\n"

      supabase_env_filename = ".env.example"
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
        env.set("POSTGRES_ADMIN_DB", config.postgres_admin_db)
        env.set("POSTGRES_ADMIN_USER", config.postgres_admin_user)
        env.set("POSTGRES_ADMIN_PASSWORD", credentials.postgres_admin_password)
        env.set("POSTGRES_APP_DB", config.postgres_app_db)
        env.set("POSTGRES_APP_USER", config.postgres_app_user)
        env.set("CADDY_DEPLOYMENT_MODE", config.caddy_deployment_mode)        
        env.set("POSTGRES_APP_PASSWORD", credentials.postgres_app_password)
        env.set("POSTGRES_AUTHENTICATOR_PASSWORD", credentials.postgres_authenticator_password)
        env.set("POSTGRES_PASSWORD", credentials.postgres_admin_password)
        env.set("ACCESS_JWT_EXPIRY", config.access_jwt_expiry)
        env.set("REFRESH_JWT_EXPIRY", config.refresh_jwt_expiry)
        env.set("JWT_SECRET", credentials.jwt_secret)
        env.set("SERVICE_ROLE_KEY", credentials.service_role_key)
        env.set("DASHBOARD_USERNAME", credentials.dashboard_username)
        env.set("DASHBOARD_PASSWORD", credentials.dashboard_password)

        # Set derived values
        env.set("SITE_URL", derived.site_url)
        env.set("API_EXTERNAL_URL", derived.api_external_url)
        env.set("API_PUBLIC_URL", derived.api_public_url)
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
    NEXT_PUBLIC_BROWSER_REST_URL=#{config.browser_api_url}
    NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME=#{config.deployment_slot_name}
    NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE=#{config.deployment_slot_code}

    # Client-side debugging for the Statbus App. Requires app rebuild/restart.
    # To enable, edit .env: set NEXT_PUBLIC_DEBUG=true and comment out/remove NEXT_PUBLIC_DEBUG=false.
    # To disable, edit .env: set NEXT_PUBLIC_DEBUG=false and comment out/remove NEXT_PUBLIC_DEBUG=true.
    # This setting is sourced from NEXT_PUBLIC_DEBUG in .env.config (defaults to false).
    #{
      if config.next_public_debug == "true"
        "NEXT_PUBLIC_DEBUG=true\n#NEXT_PUBLIC_DEBUG=false"
      else
        "#NEXT_PUBLIC_DEBUG=true\nNEXT_PUBLIC_DEBUG=false"
      end
    }
    #
    ################################################################
    EOS

      return content
    end

    # Class to hold data for the Caddyfile ECR template
    class CaddyfileTemplate
      getter domain : String
      getter deployment_user : String
      getter app_port : Int32
      getter postgrest_bind_address : String
      getter app_bind_address : String
      getter deployment_slot_code : String
      getter caddy_deployment_mode : String
      getter program_name : String
      getter caddy_http_port : Int32
      getter caddy_https_port : Int32
      getter caddy_http_bind_address : String
      getter caddy_https_bind_address : String

      def initialize(derived : DerivedEnv, config : ConfigEnv)
        @domain = derived.domain
        @deployment_user = derived.deployment_user
        @app_port = derived.app_port
        @postgrest_bind_address = derived.postgrest_bind_address
        @app_bind_address = derived.app_bind_address
        @deployment_slot_code = config.deployment_slot_code
        @caddy_deployment_mode = config.caddy_deployment_mode
        @program_name = PROGRAM_NAME
        @caddy_http_port = derived.caddy_http_port
        @caddy_https_port = derived.caddy_https_port
        @caddy_http_bind_address = derived.caddy_http_bind_address
        @caddy_https_bind_address = derived.caddy_https_bind_address
      end
    end
    
    class CaddyfilePrivateTemplate < CaddyfileTemplate
      ECR.def_to_s "src/templates/private.caddyfile.ecr"
    end
    
    class CaddyfileDevelopmentTemplate < CaddyfileTemplate
      ECR.def_to_s "src/templates/development.caddyfile.ecr"
    end
    
    class CaddyfilePublicTemplate < CaddyfileTemplate
      ECR.def_to_s "src/templates/public.caddyfile.ecr"
    end
    
    class CaddyfileStandaloneTemplate < CaddyfileTemplate
      ECR.def_to_s "src/templates/standalone.caddyfile.ecr"
    end
    
    class CaddyfileMainTemplate < CaddyfileTemplate
      ECR.def_to_s "src/templates/Caddyfile.ecr"
    end

    class CaddyfileCommonTemplate < CaddyfileTemplate
      ECR.def_to_s "src/templates/common.caddyfile.ecr"
    end
    
    # Generate all Caddyfile variants and write them to disk
    private def generate_caddy_content(derived : DerivedEnv, config : ConfigEnv)
      caddyfile_targets = {
        # Common snippets used by all configurations
        "common.caddyfile" => CaddyfileCommonTemplate.new(derived, config),
        # For development mode
        "development.caddyfile" => CaddyfileDevelopmentTemplate.new(derived, config),
        # For private mode
        "private.caddyfile" => CaddyfilePrivateTemplate.new(derived, config),
        "public.caddyfile" => CaddyfilePublicTemplate.new(derived, config),
        # For standalone mode
        "standalone.caddyfile" => CaddyfileStandaloneTemplate.new(derived, config),
        # Main file for including the right file depending on mode
        "Caddyfile" => CaddyfileMainTemplate.new(derived, config) # This is the main Caddyfile, name is literal
      }
      
      # Write each Caddyfile variant
      caddyfile_targets.each do |target_filename, template|
        content = template.to_s
        caddyfilename = "caddy/config/#{target_filename}"
        
        write_caddy_file(caddyfilename, content, derived.domain)
      end

      # Validate that the deployment mode is valid
      current_mode = config.caddy_deployment_mode
      valid_modes = ["development", "private", "standalone"]
      if !valid_modes.includes?(current_mode)
        raise "Error: Unrecognized CADDY_DEPLOYMENT_MODE '#{current_mode}'. Must be one of: #{valid_modes.join(", ")}"
      end
    end
    
    # Helper method to write a Caddyfile with proper logging
    private def write_caddy_file(filename : String, content : String, domain : String, mode : String? = nil)
      mode_info = mode ? " with #{mode} mode" : ""
      
      if File.exists?(filename)
        current_content = File.read(filename)
        if content != current_content
          puts "Updating #{filename}#{mode_info} for #{domain}" if @config.verbose
          File.write(filename, content)
        else
          puts "No changes needed in #{filename} for #{domain}" if @config.verbose
        end
      else
        puts "Creating new #{filename}#{mode_info} for #{domain}" if @config.verbose
        File.write(filename, content)
      end
    end
  end
end
