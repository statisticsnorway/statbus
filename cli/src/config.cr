require "poncho"

class StatBusConfig
  include Poncho

  property postgres_host : String
  property postgres_port : String
  property postgres_db : String
  property postgres_user : String
  property postgres_password : String

  def initialize(project_directory : Path)
    @postgres_host = "127.0.0.1"
    @postgres_user = "postgres"
    env_path = project_directory.join(".env")
    puts env_path.to_s
    env_config = Poncho.from_file(env_path.to_s)
    @postgres_port = env_config["DB_PUBLIC_LOCALHOST_PORT"]? || raise "Missing DB_PUBLIC_LOCALHOST_PORT in .env"
    @postgres_db = env_config["POSTGRES_DB"]? || raise "Missing POSTGRES_DB in .env"
    @postgres_password = env_config["POSTGRES_PASSWORD"]? || raise "Missing POSTGRES_PASSWORD in .env"
  end

  def connection_string : String
    "postgres://#{postgres_user}:#{postgres_password}@#{postgres_host}:#{postgres_port}/#{postgres_db}"
  end
end
