require "poncho"

class StatBusConfig
  include Poncho

  property postgres_host : String
  property postgres_port : String
  property postgres_db : String
  property postgres_user : String
  property postgres_password : String

  def initialize(project_directory : Path, @verbose : Bool)
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

  def connection_string : String
    "postgres://#{postgres_user}:#{postgres_password}@#{postgres_host}:#{postgres_port}/#{postgres_db}"
  end
end
