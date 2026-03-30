require "json"
require "time"
require "option_parser"
require "pg"
require "csv"
require "yaml"
require "./dotenv"
require "./config"
require "./import"
require "./worker"

module Statbus
  # Compatibility helper for Time.instant (Crystal 1.19+) vs Time.monotonic (older)
  # Time.monotonic was deprecated in favor of Time.instant in Crystal 1.19.0
  macro monotonic_time
    {% if compare_versions(Crystal::VERSION, "1.19.0") >= 0 %}
      Time.instant
    {% else %}
      Time.monotonic
    {% end %}
  end
  class Cli
    enum Mode
      Worker
    end

    @name = "statbus"
    @mode : Mode | Nil = nil

    def initialize
      @config = Config.new
      @worker = Worker.new(@config)
      begin
        option_parser = build_option_parser
        option_parser.parse

        if @config.debug
          puts "Final debug settings after command line parsing:"
          puts "  verbose=#{@config.verbose}"
          puts "  debug=#{@config.debug}"
        end

        run(option_parser)
      rescue ex : ArgumentError
        puts ex
        exit 1
      end
    end

    private def build_option_parser
      OptionParser.new do |parser|
        parser.banner = "Usage: #{@name} [subcommand] [arguments]"
        parser.on("-v", "--verbose", "Enable verbose output") { @config.verbose = true }
        parser.on("-d", "--debug", "Enable debug output") { @config.debug = true }
        parser.on("-q", "--quiet", "Disable verbose output (overrides VERBOSE env var)") { @config.verbose = false }
        parser.on("-h", "--help", "Show help, available for subcommands") do
          puts parser
          exit
        end
        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts parser
          exit(1)
        end
        parser.on("worker", "Run Statbus Worker for background processing") do
          @mode = Mode::Worker
          parser.on("--stop-when-idle", "Exit when all queues are idle (for testing)") do
            @worker.stop_when_idle = true
          end
          parser.on("--database DB", "Override database name") do |db|
            @config.postgres_db = db
          end
        end
      end
    end

    private def run(option_parser : OptionParser)
      case @mode
      in Mode::Worker
        puts "Starting worker with verbose=#{@config.verbose}, debug=#{@config.debug}" if @config.verbose
        @worker.run
      in nil
        puts "StatBus is a locally installable STATistical BUSiness registry"
        puts option_parser
      end
    end
  end
end
