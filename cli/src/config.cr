require "poncho"

class Config
  include Poncho

  property postgres_host : String = "127.0.0.1"
  property postgres_port : String = "5432"
  property postgres_db : String = "postgres"
  property postgres_user : String = "postgres"
  property postgres_password : String = ""

  property project_directory : Path
  property working_directory = Dir.current
  # Initialize with environment variables, but allow command line flags to override
  property verbose : Bool = false
  property debug : Bool = false

  def initialize_from_env
    @verbose = ENV["VERBOSE"]? == "1" || ENV["VERBOSE"]?.try(&.downcase) == "true" || false
    @debug = ENV["DEBUG"]? == "1" || ENV["DEBUG"]?.try(&.downcase) == "true" || false
  end

  def initialize
    # Initialize debug flags from environment variables
    initialize_from_env
    
    # Log initial environment-based settings if they were set
    if ENV["VERBOSE"]? || ENV["DEBUG"]?
      puts "Environment settings detected:"
      puts "  VERBOSE=#{ENV["VERBOSE"]?}" if ENV["VERBOSE"]?
      puts "  DEBUG=#{ENV["DEBUG"]?}" if ENV["DEBUG"]?
    end
    @project_directory = initialize_project_directory
    
    # Detect if running in Docker using environment variable
    running_in_docker = ENV["RUNNING_IN_DOCKER"]? == "true"
    
    # Configure database connection based on environment
    if running_in_docker
      # In Docker, use the container names and internal Docker network port
      @postgres_host = ENV["POSTGRES_HOST"]? || @postgres_host
      @postgres_port = ENV["POSTGRES_PORT"]? || "5432" # Default PostgreSQL port inside Docker network
    else
      # In development (local), use localhost
      @postgres_host = "127.0.0.1"
      # Port will be set from .env file below if available
    end
    
    # Common settings for all environments
    @postgres_user = ENV["POSTGRES_USER"]? || @postgres_user
    
    if db = ENV["POSTGRES_DB"]?
      @postgres_db = db
    end
    
    if password = ENV["POSTGRES_PASSWORD"]?
      @postgres_password = password
    end

    # Try to read from .env file for additional configuration
    env_path = project_directory.join(".env")
    if @verbose
      puts "Looking for .env at: #{env_path}"
      puts "Current directory: #{Dir.current}"
      puts "Project directory: #{project_directory}"
      puts "Running in Docker: #{running_in_docker}"
    end

    if File.exists?(env_path)
      puts "Found .env file" if @verbose
      env_config = Poncho.from_file(env_path.to_s)
      
      # Use values from .env if they exist and weren't set from environment variables
      if !running_in_docker
        # In local development, use the public localhost port from .env
        if env_port = env_config["DB_PUBLIC_LOCALHOST_PORT"]?
          @postgres_port = env_port
        end
      end
      
      if env_db = env_config["POSTGRES_DB"]?
        @postgres_db = env_db
      end
      
      if env_password = env_config["POSTGRES_PASSWORD"]?
        @postgres_password = env_password
      end
    end
    
    if @verbose
      puts "Final configuration:"
      puts "  Host: #{@postgres_host}"
      puts "  Port: #{@postgres_port}"
      puts "  Database: #{@postgres_db}"
      puts "  User: #{@postgres_user}"
    end
  end

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

  def connection_string : String
    "postgres://#{postgres_user}:#{postgres_password}@#{postgres_host}:#{postgres_port}/#{postgres_db}"
  end
end
