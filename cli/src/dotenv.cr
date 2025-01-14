require "option_parser"
require "file_utils"

# The Dotenv class provides functionality to read and manipulate .env files
# containing environment variables in KEY=VALUE format.
#
# Example usage:
#
# ```
# # Load variables from .env file
# dotenv = Dotenv.from_file(".env")
#
# # Get a value
# api_key = dotenv.get("API_KEY")
# puts api_key # => "secret123"
#
# # Set a value (creates or updates)
# dotenv.set("DEBUG", "true")
#
# # Set a default value (only if key doesn't exist)
# dotenv.set("PORT", "+3000") # '+' prefix means "default"
#
# # Parse specific keys
# values = dotenv.parse(["API_KEY", "DEBUG"])
# puts values # => {"API_KEY" => "secret123", "DEBUG" => "true"}
#
# # Export all variables to ENV
# dotenv.export
# puts ENV["API_KEY"] # => "secret123"
#
# # Generate a value from command output
# dotenv.generate("TIMESTAMP") { Time.utc.to_s }
# ```
#
# The class preserves file formatting including:
# - Comments (both full-line and inline)
# - Blank lines
# - Leading whitespace
# - Original line ordering
class Dotenv
  @@key : String | Nil = nil

  class Error < Exception; end

  # Represents different types of lines in a .env file
  abstract class EnvLine
    property content : String

    def initialize(@content)
    end

    abstract def to_s : String
  end

  # Represents a blank line
  class BlankLine < EnvLine
    def to_s : String
      @content
    end
  end

  # Represents a comment line starting with #
  class CommentLine < EnvLine
    def to_s : String
      @content
    end
  end

  # Represents an invalid/malformed line that should be preserved
  class InvalidLine < EnvLine
    def to_s : String
      @content
    end
  end

  # Represents a key-value pair with optional leading whitespace and inline comment
  class KeyValueLine < EnvLine
    property key : String
    property value : String
    property leading_whitespace : String
    property inline_comment : String?

    def initialize(@key, @value, @leading_whitespace = "", @inline_comment = nil)
      super("#{@leading_whitespace}#{@key}=#{@value}#{@inline_comment ? " #{@inline_comment}" : ""}")
    end

    def to_s : String
      "#{@leading_whitespace}#{@key}=#{@value}#{@inline_comment ? "#{@inline_comment}" : ""}"
    end
  end

  # Represents the entire .env file
  class EnvFile
    property lines : Array(EnvLine)
    property mapping : Hash(String, KeyValueLine)

    def initialize
      @lines = [] of EnvLine
      @mapping = {} of String => KeyValueLine
    end

    def get(key : String) : String?
      @mapping[key]?.try(&.value)
    end

    def set(key : String, value : String)
      if line = @mapping[key]?
        # Update existing line
        line.value = value
        line.content = line.to_s
      else
        # Add new line
        line = KeyValueLine.new(key, value)
        @lines << line
        @mapping[key] = line
      end
    end

    def parse(keys : Array(String) = [] of String) : Hash(String, String)
      result = {} of String => String
      @mapping.each do |key, line|
        if keys.empty? || keys.includes?(key)
          result[key] = line.value
        end
      end
      result
    end

    def to_s : String
      @lines.map(&.to_s).join("\n")
    end
  end

  property env_file : EnvFile
  property dotenv_file : String
  property verbose : Bool

  def initialize(@dotenv_file = ".env", @verbose = false)
    @env_file = EnvFile.new
    load_file
  end

  def self.from_file(file : String, verbose = false) : Dotenv
    new(file, verbose)
  end

  # Parses a line into an appropriate EnvLine object
  private def parse_line(line : String) : EnvLine
    case
    when line.strip.empty?
      BlankLine.new(line)
    when line.strip.starts_with?("#")
      CommentLine.new(line)
    else
      if match = line.match(/^(\s*)([^#=]+)=([^#]*?)(\s+#.*)?$/)
        whitespace = match[1]
        key = match[2].strip
        value = match[3]
        comment = match[4]?
        KeyValueLine.new(key, value, whitespace, comment.presence)
      else
        InvalidLine.new(line)
      end
    end
  end

  # Appends a line to the .env file and updates the in-memory representation
  def puts(line : String)
    env_line = parse_line(line)
    if env_line.is_a?(KeyValueLine)
      STDERR.puts "Adding line: #{env_line.key}=#{env_line.value}" if @verbose
      File.open(@dotenv_file, "a") do |file|
        file.puts(line)
      end
      @env_file.lines << env_line
      @env_file.mapping[env_line.key] = env_line
    else
      File.open(@dotenv_file, "a") do |file|
        file.puts(line)
      end
      @env_file.lines << env_line
    end
  end

  # Loads and parses the .env file into memory
  def load_file
    return unless File.exists?(@dotenv_file)

    STDERR.puts "Loading #{@dotenv_file}" if @verbose
    @env_file = EnvFile.new

    File.each_line(@dotenv_file) do |line|
      env_line = parse_line(line)
      @env_file.lines << env_line
      if env_line.is_a?(KeyValueLine)
        STDERR.puts "Loaded: #{env_line.key}=#{env_line.value}" if @verbose
        @env_file.mapping[env_line.key] = env_line
      end
    end
    STDERR.puts "Finished loading #{@dotenv_file}" if @verbose
  end

  def save_file
    STDERR.puts "Saving to #{@dotenv_file}" if @verbose
    File.write(@dotenv_file, @env_file.to_s)
    STDERR.puts "Saved #{@env_file.mapping.size} entries" if @verbose
  end

  def get(key : String) : String?
    value = @env_file.get(key)
    STDERR.puts "Getting #{key}=#{value}" if @verbose
    return value
  end

  # Sets or updates an environment variable
  # If value starts with "+", only sets if key doesn't exist (default value)
  def set(key : String, value : String)
    STDERR.puts "Setting #{key}" if @verbose
    if value.starts_with?("+")
      default_value = value[1..-1]
      if @env_file.mapping.has_key?(key)
        STDERR.puts "Key #{key} exists, keeping current value" if @verbose
      else
        STDERR.puts "Key #{key} not found, setting default: #{default_value}" if @verbose
        @env_file.set(key, default_value)
      end
    else
      STDERR.puts "Setting #{key}=#{value}" if @verbose
      @env_file.set(key, value)
    end
    save_file
  end

  def export
    @env_file.mapping.each { |k, v| ENV[k] = v.value }
  end

  def parse(keys : Array(String) = [] of String)
    @env_file.parse(keys)
  end

  def generate(key : String, &block : -> String)
    return if @env_file.mapping[key]?
    value = block.call
    @env_file.set(key, value)
    save_file
  end

  def self.run(dotenv_file : String = ".env")
    dotenv = from_file(dotenv_file)
    option_parser = OptionParser.parse do |parser|
      parser.banner = "Usage: dotenv [options]"

      parser.on("-v", "--verbose", "Enable verbose output") { dotenv.verbose = true }

      parser.on("-f FILE", "--file=FILE", "Specify dotenv file") do |file|
        dotenv = from_file(file, dotenv.verbose)
      end

      parser.on("get", "Get the value of a key") do
        parser.on("-k KEY", "--key KEY", "The key") do |key|
          puts "Got a key #{key}"
          @@key = key
        end
        key = @@key
        if key.nil? || key == ""
          puts "Error: get requires a key"
          exit(1)
        else
          puts dotenv.get(key) || "Key not found"
        end
      end

      parser.on("set KEY=VALUE", "Set the value of a key") do |pair|
        key, value = pair.split("=", 2)
        dotenv.set(key, value)
      end

      parser.on("export", "Export all keys to environment") do
        dotenv.export
      end

      parser.on("parse [KEYS...]", "Parse and print keys") do |keys|
        keys_array = keys.is_a?(Array) ? keys : [] of String
        puts dotenv.parse(keys_array).map { |k, v| "#{k}=#{v}" }.join("\n")
      end

      parser.on("generate KEY CMD", "Generate a key using a command") do |args|
        key, cmd = args.split(" ", 2)
        dotenv.generate(key) { `#{cmd}`.strip }
      end

      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
    end
  end
end

if File.basename(Path.new(PROGRAM_NAME)) == File.basename(Path.new(__FILE__), ".cr")
  Dotenv.run
end
