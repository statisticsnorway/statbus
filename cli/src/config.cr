require "poncho"

class Config
  include Poncho

  property postgres_host : String
  property postgres_port : String
  property postgres_db : String
  property postgres_user : String
  property postgres_password : String

  property project_directory : Path
  property working_directory = Dir.current
  property verbose = false
  property debug = false
  property project_directory : Path

  def initialize
    @project_directory = initialize_project_directory

    @postgres_host = "127.0.0.1"
    @postgres_user = "postgres"
    env_path = project_directory.join(".env")
    if @verbose
      puts "Looking for .env at: #{env_path}"
      puts "Current directory: #{Dir.current}"
      puts "Project directory: #{project_directory}"
    end

    if File.exists?(env_path)
      puts "Found .env file" if @verbose
      env_config = Poncho.from_file(env_path.to_s)
    else
      raise "Could not find .env file at #{env_path}"
    end
    @postgres_port = env_config["DB_PUBLIC_LOCALHOST_PORT"]? || raise "Missing DB_PUBLIC_LOCALHOST_PORT in .env"
    @postgres_db = env_config["POSTGRES_DB"]? || raise "Missing POSTGRES_DB in .env"
    @postgres_password = env_config["POSTGRES_PASSWORD"]? || raise "Missing POSTGRES_PASSWORD in .env"
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
