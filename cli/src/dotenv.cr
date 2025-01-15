require "commander"
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
    property quote : Char?

    def initialize(@key, @value, @leading_whitespace = "", @inline_comment = nil, @quote = nil)
      super("#{@leading_whitespace}#{@key}=#{@value}#{@inline_comment ? " #{@inline_comment}" : ""}")
    end

    def to_s : String
      quoted_value = @quote ? "#{@quote}#{@value}#{@quote}" : @value
      "#{@leading_whitespace}#{@key}=#{quoted_value}#{@inline_comment ? "#{@inline_comment}" : ""}"
    end
  end

  # Represents the entire .env file
  class DotenvContent
    property lines : Array(EnvLine)
    property mapping : Hash(String, KeyValueLine)

    def initialize
      @lines = [] of EnvLine
      @mapping = {} of String => KeyValueLine
    end

    def get(key : String) : String?
      @mapping[key]?.try(&.value)
    end

    # Sets or updates a dotenv variable value
    # Returns the value that was set
    def set(key : String, value : String) : String
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
      value
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

  property dotenv_content : DotenvContent
  property dotenv_path : Path?
  property verbose : Bool

  def initialize(dotenv_path : String | Path | Nil = ".env", content : String? = nil, @verbose = false)
    @dotenv_path = dotenv_path.try { |path| path.is_a?(Path) ? path : Path.new(path) }
    @dotenv_content = DotenvContent.new

    if content
      parse_content(content)
    elsif dotenv_path
      load_file
    end
  end

  def self.from_file(file : String | Path, verbose = false) : Dotenv
    new(dotenv_path: file, verbose: verbose)
  end

  def self.from_string(content : String, verbose = false) : Dotenv
    new(dotenv_path: nil, content: content, verbose: verbose)
  end

  # Opens a .env file or parses content, yields it to the block, and saves if modified
  # and we have a Path.
  def self.using(source : Path | String, verbose = false, &block : Dotenv -> T) forall T
    dotenv = case source
             when Path
               from_file(source, verbose)
             when String
               from_string(source, verbose)
             else
               raise "Unsupported source type"
             end

    initial_content = dotenv.dotenv_content.to_s
    result = block.call(dotenv)

    # Only save if content changed and we're working with a file
    if source.is_a?(Path) && dotenv.dotenv_content.to_s != initial_content
      dotenv.save_file
    end

    return result
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

        # Handle quotes
        quote = nil
        if value.starts_with?('"') && value.ends_with?('"') ||
           value.starts_with?('\'') && value.ends_with?('\'')
          quote = value[0]
          value = value[1..-2] # Strip quotes
        end

        KeyValueLine.new(key, value, whitespace, comment.presence, quote)
      else
        InvalidLine.new(line)
      end
    end
  end

  # Appends a line to the dotenv contents and updates the in-memory representation
  def puts(line : String)
    env_line = parse_line(line)
    if env_line.is_a?(KeyValueLine)
      STDERR.puts "Adding line: #{env_line.key}=#{env_line.value}" if @verbose
      File.open(@dotenv_path, "a") do |file|
        file.puts(line)
      end
      @dotenv_content.lines << env_line
      @dotenv_content.mapping[env_line.key] = env_line
    else
      File.open(@dotenv_path, "a") do |file|
        file.puts(line)
      end
      @dotenv_content.lines << env_line
    end
  end

  # Loads and parses the .env file into memory
  # Parses content from a string
  def parse_content(content : String)
    STDERR.puts "Parsing content" if @verbose
    @dotenv_content = DotenvContent.new

    content.each_line do |line|
      env_line = parse_line(line)
      @dotenv_content.lines << env_line
      if env_line.is_a?(KeyValueLine)
        STDERR.puts "Parsed: #{env_line.key}=#{env_line.value}" if @verbose
        @dotenv_content.mapping[env_line.key] = env_line
      end
    end
  end

  # Loads and parses from a file
  def load_file
    return unless @dotenv_path && File.exists?(@dotenv_path.not_nil!)

    STDERR.puts "Loading #{@dotenv_path}" if @verbose
    parse_content(File.read(@dotenv_path.not_nil!))
    STDERR.puts "Finished loading #{@dotenv_path}" if @verbose
  end

  def save_file
    raise "Cannot save - no path specified" unless @dotenv_path

    STDERR.puts "Saving to #{@dotenv_path}" if @verbose
    File.write(@dotenv_path.not_nil!, @dotenv_content.to_s)
    STDERR.puts "Saved #{@dotenv_content.mapping.size} entries" if @verbose
  end

  def get(key : String) : String?
    value = @dotenv_content.get(key)
    STDERR.puts "Getting #{key}=#{value}" if @verbose
    return value
  end

  # Sets or updates an environment variable
  # If value starts with "+", only sets if key doesn't exist (default value)
  def set(key : String, value : String)
    STDERR.puts "Setting #{key}" if @verbose
    if value.starts_with?("+")
      default_value = value[1..-1]
      if @dotenv_content.mapping.has_key?(key)
        STDERR.puts "Key #{key} exists, keeping current value" if @verbose
      else
        STDERR.puts "Key #{key} not found, setting default: #{default_value}" if @verbose
        @dotenv_content.set(key, default_value)
      end
    else
      STDERR.puts "Setting #{key}=#{value}" if @verbose
      @dotenv_content.set(key, value)
    end
  end

  def export
    @dotenv_content.mapping.each { |k, v| ENV[k] = v.value }
  end

  def parse(keys : Array(String) = [] of String)
    @dotenv_content.parse(keys)
  end

  # Generates a value for a key if it doesn't exist
  # Returns the generated value or the existing value
  def generate(key : String, &block : -> String) : String
    if existing = @dotenv_content.mapping[key]?
      existing.value
    else
      value = block.call
      @dotenv_content.set(key, value)
      value
    end
  end

  def self.run(dotenv_filename : String = ".env")
    cli = Commander::Command.new do |cmd|
      cmd.use = "dotenv"
      cmd.long = "Manage .env files containing environment variables"

      # Global flags
      cmd.flags.add do |flag|
        flag.name = "file"
        flag.short = "-f"
        flag.long = "--file"
        flag.default = ".env"
        flag.description = "Specify dotenv file"
        flag.persistent = true
      end

      cmd.flags.add do |flag|
        flag.name = "verbose"
        flag.short = "-v"
        flag.long = "--verbose"
        flag.default = false
        flag.description = "Enable verbose output"
        flag.persistent = true
      end

      # Get command
      cmd.commands.add do |cmd|
        cmd.use = "get <key>"
        cmd.short = "Get the value of a key"
        cmd.long = cmd.short
        cmd.run do |options, arguments|
          dotenv = self.from_file(options.string["file"], options.bool["verbose"])
          key = arguments[0]?
          if key.nil? || key.empty?
            STDERR.puts "Error: get requires a key"
            exit(1)
          else
            puts dotenv.get(key) || "Key not found"
          end
        end
      end

      # Set command
      cmd.commands.add do |cmd|
        cmd.use = "set <key> <value>"
        cmd.short = "Set the value of a key"
        cmd.long = cmd.short
        cmd.run do |options, arguments|
          dotenv = self.from_file(options.string["file"], options.bool["verbose"])
          key = arguments[0]?
          value = arguments[1]?
          if key.nil? || value.nil?
            STDERR.puts "Error: set requires key and value"
            exit(1)
          else
            dotenv.set(key, value)
            dotenv.save_file
          end
        end
      end

      # Export command
      cmd.commands.add do |cmd|
        cmd.use = "export"
        cmd.short = "Export all keys to environment"
        cmd.long = cmd.short
        cmd.run do |options, arguments|
          dotenv = self.from_file(options.string["file"], options.bool["verbose"])
          dotenv.export
        end
      end

      # Parse command
      cmd.commands.add do |cmd|
        cmd.use = "parse [keys...]"
        cmd.short = "Parse and print specified keys (or all if none specified)"
        cmd.long = cmd.short
        cmd.run do |options, arguments|
          dotenv = self.from_file(options.string["file"], options.bool["verbose"])
          puts dotenv.parse(arguments).map { |k, v| "#{k}=#{v}" }.join("\n")
        end
      end

      # Generate command
      cmd.commands.add do |cmd|
        cmd.use = "generate <key> <command>"
        cmd.short = "Generate a key using a shell command"
        cmd.long = cmd.short
        cmd.run do |options, arguments|
          dotenv = self.from_file(options.string["file"], options.bool["verbose"])
          key = arguments[0]?
          command = arguments[1]?
          if key.nil? || command.nil?
            STDERR.puts "Error: generate requires key and command"
            exit(1)
          else
            dotenv.generate(key) { `#{command}`.strip }
            dotenv.save_file
          end
        end
      end

      # Default command if no other match
      cmd.run do |options, arguments|
        puts cmd.help
      end
    end

    Commander.run(cli, ARGV)
  end
end

# Support running as a standalone binary or as a crystal script.
file_name = File.basename(Path.new(__FILE__), ".cr")
script_name = "crystal-run-#{file_name}.tmp"
executable_name = File.basename(Path.new(PROGRAM_NAME))

if file_name == executable_name || script_name == executable_name
  Dotenv.run
end
