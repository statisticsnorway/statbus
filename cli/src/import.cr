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

module Statbus
  class Import
    enum Mode
      LegalUnit
      Establishment
    end
    enum Strategy
      Copy
      Insert
    end

    # Properties
    property mode : Mode | Nil = nil
    property delayed_constraint_checking = true
    property refresh_materialized_views = true
    property import_file_name : String | Nil = nil
    property config_field_mapping = Array(ConfigFieldMapping).new
    property config_field_mapping_file_path : Path | Nil = nil
    property sql_field_mapping = Array(SqlFieldMapping).new
    property import_strategy = Strategy::Copy
    property import_tag : String | Nil = nil
    property offset = 0
    property valid_from : String = Time.utc.to_s("%Y-%m-%d")
    property valid_to = "infinity"
    property user_email : String | Nil = nil

    def initialize(config : Config)
      @config = config
    end

    def run(option_parser : OptionParser)
      if @import_file_name.nil? || @user_email.nil?
        if @import_file_name.nil?
          STDERR.puts "missing required name of file to read from"
        end
        if @user_email.nil?
          STDERR.puts "missing required user email (use -u or --user)"
        end
        puts option_parser
        exit(1)
      else
        case @mode
        in Import::Mode::LegalUnit
          import_legal_units(import_file_name.not_nil!)
        in Import::Mode::Establishment
          import_establishments(import_file_name.not_nil!)
        in nil
          puts option_parser
          exit(1)
        end
      end
    end

    def import_legal_units(import_file_name : String)
      puts "Importing legal units"
      sql_field_required_list = ["tax_ident"]
      sql_field_optional_list = [
        "name",
        "birth_date",
        "death_date",
        "physical_address_part1",
        "physical_address_part2",
        "physical_address_part3",
        "physical_postcode",
        "physical_postplace",
        "physical_region_code",
        "physical_region_path",
        "physical_country_iso_2",
        "postal_address_part1",
        "postal_address_part2",
        "postal_address_part3",
        "postal_postcode",
        "postal_postplace",
        "postal_region_code",
        "postal_region_path",
        "postal_country_iso_2",
        "primary_activity_category_code",
        "secondary_activity_category_code",
        "sector_code",
        "legal_form_code",
      ]
      upload_view_name = "import_legal_unit_era"
      import_common(import_file_name, sql_field_required_list, sql_field_optional_list, upload_view_name)
    end

    def import_establishments(import_file_name : String)
      puts "Importing establishments"
      sql_field_required_list = [
        "tax_ident",
      ]
      sql_field_optional_list = [
        "legal_unit_tax_ident",
        "name",
        "birth_date",
        "death_date",
        "physical_address_part1",
        "physical_address_part2",
        "physical_address_part3",
        "physical_postcode",
        "physical_postplace",
        "physical_region_code",
        "physical_region_path",
        "physical_country_iso_2",
        "postal_address_part1",
        "postal_address_part2",
        "postal_address_part3",
        "postal_postcode",
        "postal_postplace",
        "postal_region_code",
        "postal_region_path",
        "postal_country_iso_2",
        "primary_activity_category_code",
        "secondary_activity_category_code",
        "sector_code",
        "employees",
        "turnover",
      ]
      upload_view_name = "import_establishment_era"
      import_common(import_file_name, sql_field_required_list, sql_field_optional_list, upload_view_name)
    end

    private def import_common(import_file_name, sql_field_required_list, sql_field_optional_list, upload_view_name)
      # Find .env and load required secrets
      config = Config.new
      Dir.cd(@config.project_directory) do
        puts "Import data to #{config.connection_string}" if @config.verbose

        sql_cli_provided_fields = ["valid_from", "valid_to", "tag_path"]
        sql_fields_list = sql_cli_provided_fields + sql_field_required_list + sql_field_optional_list
        file_stream =
          Dir.cd(@config.working_directory) do
            File.open(import_file_name)
          end
        csv_stream = CSV.new(file_stream, headers: true, separator: ',', quote_char: '"')
        csv_fields_list = csv_stream.headers
        # For every equal header, insert a mapping.
        sql_field_required = sql_field_required_list.to_set
        puts "sql_field_required #{sql_field_required}" if @config.verbose
        sql_fields = sql_fields_list.to_set
        puts "sql_field #{sql_fields}" if @config.verbose
        csv_fields = csv_fields_list.to_set
        puts "csv_fields #{csv_fields}" if @config.verbose
        common_fields = sql_fields & csv_fields
        puts "common_fields #{common_fields}" if @config.verbose
        common_fields.each do |common_field|
          @config_field_mapping.push(ConfigFieldMapping.new(sql: common_field, csv: common_field))
        end
        puts "@config_field_mapping #{@config_field_mapping}" if @config.verbose
        puts "@sql_field_mapping only common fields #{@sql_field_mapping}" if @config.verbose
        @config_field_mapping.each do |mapping|
          if !(mapping.csv.nil? || mapping.sql.nil?)
            @sql_field_mapping.push(SqlFieldMapping.from_config_field_mapping(mapping))
          end
        end
        puts "@sql_field_mapping #{@sql_field_mapping}" if @config.verbose
        mapped_sql_field = @sql_field_mapping.map(&.sql).to_set
        puts "mapped_sql_field #{mapped_sql_field}" if @config.verbose
        mapped_csv_field = @config_field_mapping.map(&.csv).to_set
        puts "mapped_csv_field #{mapped_csv_field}" if @config.verbose
        missing_required_sql_fields = sql_field_required - mapped_sql_field

        ignored_sql_field = @config_field_mapping.select { |m| m.csv.nil? }.map(&.sql).to_set
        puts "ignored_sql_field #{ignored_sql_field}" if @config.verbose
        ignored_csv_field = @config_field_mapping.select { |m| m.sql.nil? }.map(&.csv).to_set
        puts "ignored_csv_field #{ignored_csv_field}" if @config.verbose
        # Check the fields
        missing_config_sql_fields = sql_fields - sql_cli_provided_fields - mapped_sql_field - ignored_sql_field
        puts "missing_config_sql_fields #{missing_config_sql_fields}" if @config.verbose

        if missing_required_sql_fields.any? || missing_config_sql_fields.any?
          # Build the empty mappings for displaying a starting point to the user:
          # For every absent header, insert an absent mapping.
          missing_config_sql_fields.each do |sql_field|
            @config_field_mapping.push(ConfigFieldMapping.new(sql: sql_field, csv: "null"))
          end
          missing_config_csv_fields = csv_fields - mapped_csv_field - ignored_csv_field
          puts "missing_config_csv_fields #{missing_config_csv_fields}" if @config.verbose
          missing_config_csv_fields.each do |csv_field|
            @config_field_mapping.push(ConfigFieldMapping.new(sql: "null", csv: csv_field))
          end
          # Now there is a mapping for every field.
          # This mapping can be printed for the user.
          puts "Example mapping:"
          Dir.cd(@config.working_directory) do
            if !@config_field_mapping_file_path.nil?
              if !File.exists?(@config_field_mapping_file_path.not_nil!)
                File.write(
                  @config_field_mapping_file_path.not_nil!,
                  @config_field_mapping.to_pretty_json
                )
              end
            end
          end

          raise ArgumentError.new("Missing sql fields #{missing_config_sql_fields.to_a.to_pretty_json} you need to add a mapping")
        end

        puts "@config_field_mapping = #{@config_field_mapping}" if @config.verbose

        Dir.cd(@config.working_directory) do
          if !@config_field_mapping_file_path.nil?
            if !File.exists?(@config_field_mapping_file_path.not_nil!)
              puts "Writing file #{@config_field_mapping_file_path}"
              File.write(
                @config_field_mapping_file_path.not_nil!,
                @config_field_mapping.to_pretty_json
              )
              puts @config_field_mapping.to_pretty_json
            end
          end
        end

        db_connection_string = config.connection_string
        puts db_connection_string if @config.verbose
        DB.connect(db_connection_string) do |db|
          if !@import_tag.nil?
            tag = db.query_one?("
            SELECT id, path::text, name, context_valid_from::text, context_valid_to::text
            FROM public.tag
            WHERE path = $1", @import_tag,
              as: {id: Int32, path: String, name: String, context_valid_from: String?, context_valid_to: String?}
            )
            if tag.nil?
              raise ArgumentError.new("Unknown tag #{@import_tag}")
            elsif tag[:context_valid_from].nil? || tag[:context_valid_to].nil?
              raise ArgumentError.new("Tag #{tag[:path]} is missing context dates")
            end
            puts "Found tag #{tag}" if @config.verbose
            @valid_from = tag[:context_valid_from].not_nil!
            @valid_to = tag[:context_valid_to].not_nil!
          end

          # Verify user exists
          user = db.query_one?(
            "SELECT id::TEXT FROM auth.users WHERE email = $1",
            @user_email,
            as: {id: String}
          )

          if user.nil?
            raise ArgumentError.new("User with email #{@user_email} not found")
          end

          @sql_field_mapping = [
            SqlFieldMapping.new(sql: "valid_from", value: @valid_from),
            SqlFieldMapping.new(sql: "valid_to", value: @valid_to),
            if !@import_tag.nil?
              SqlFieldMapping.new(sql: "tag_path", value: @import_tag)
            end,
          ].compact + @sql_field_mapping

          puts "@sql_field_mapping = #{@sql_field_mapping}" if @config.verbose

          # Sort header mappings based on position in sql_fields_list
          @sql_field_mapping.sort_by! do |mapping|
            index = sql_fields_list.index(mapping.sql)
            if index.nil?
              raise ArgumentError.new("Found mapping for non existing sql field #{mapping.sql}")
            end
            # Every field found is order according to its position
            {1, index.not_nil!, ""}
          end

          sql_fields_str = @sql_field_mapping.map do |mapping|
            if !mapping.sql.nil?
              db.escape_identifier(mapping.sql.not_nil!)
            end
          end.compact.join(",")
          puts "sql_fields_str = #{sql_fields_str}" if @config.verbose

          case @import_strategy
          when Strategy::Copy
            db.exec "CALL test.set_user_from_email($1)", @user_email
            copy_stream = db.exec_copy "COPY public.#{upload_view_name}(#{sql_fields_str}) FROM STDIN"
            start_time = Statbus.monotonic_time
            row_count = 0

            iterate_csv_stream(csv_stream) do |sql_row, csv_row|
              sql_row.any? do |value|
                if !value.nil? && value.includes?("\t")
                  raise ArgumentError.new("Found illegal character TAB \\t in row #{csv_row}")
                end
              end
              sql_text = sql_row.join("\t")
              puts "Uploading #{sql_text}" if @config.verbose
              copy_stream.puts sql_text
              row_count += 1
              nil
            end
            puts "Waiting for processing" if @config.verbose
            copy_stream.close

            total_duration = Statbus.monotonic_time - start_time
            total_rows_per_second = row_count / total_duration.total_seconds
            puts "Total rows processed: #{row_count}"
            puts "Total time: #{total_duration.total_seconds.round(2)} seconds (#{total_rows_per_second.round(2)} rows/second)"

            db.close
          when Strategy::Insert
            sql_args = (1..(@sql_field_mapping.size)).map { |i| "$#{i}" }.join(",")
            sql_statement = "INSERT INTO public.#{upload_view_name}(#{sql_fields_str}) VALUES(#{sql_args})"
            puts "sql_statement = #{sql_statement}" if @config.verbose
            db.exec "BEGIN;"
            db.exec "CALL test.set_user_from_email($1)", @user_email
            # Set a config that prevents inner trigger functions form activating constraints,
            # make the deferral moot.
            if @delayed_constraint_checking
              db.exec "SET LOCAL statbus.constraints_already_deferred TO 'true';"
              db.exec "SET CONSTRAINTS ALL DEFERRED;"
            end
            start_time = Statbus.monotonic_time
            batch_start_time = start_time
            row_count = 0
            insert = db.build sql_statement
            batch_size = 10000
            batch_item = 0
            iterate_csv_stream(csv_stream) do |sql_row, csv_row|
              batch_item += 1
              row_count += 1
              puts "Uploading #{sql_row}" if @config.verbose
              insert.exec(args: sql_row)
              -> {
                if (batch_item % batch_size) == 0
                  puts "Commit-ing changes"
                  if @delayed_constraint_checking
                    db.exec "SET CONSTRAINTS ALL IMMEDIATE;"
                  end
                  db.exec "END;"

                  batch_duration = Statbus.monotonic_time - batch_start_time
                  batch_rows_per_second = batch_size / batch_duration.total_seconds
                  puts "Processed #{batch_size} rows in #{batch_duration.total_seconds.round(2)} seconds (#{batch_rows_per_second.round(2)} rows/second)"
                  batch_start_time = Statbus.monotonic_time

                  db.exec "BEGIN;"
                  db.exec "CALL test.set_user_from_email($1)", @user_email
                  if @delayed_constraint_checking
                    db.exec "SET LOCAL statbus.constraints_already_deferred TO 'true';"
                    db.exec "SET CONSTRAINTS ALL DEFERRED;"
                  end
                  insert = db.build sql_statement
                end
              }
            end
            puts "Commit-ing changes"
            if @delayed_constraint_checking
              db.exec "SET CONSTRAINTS ALL IMMEDIATE;"
            end
            db.exec "END;"

            total_duration = Statbus.monotonic_time - start_time
            total_rows_per_second = row_count / total_duration.total_seconds
            puts "Total rows processed: #{row_count}"
            puts "Total time: #{total_duration.total_seconds.round(2)} seconds (#{total_rows_per_second.round(2)} rows/second)"

            db.close
          end
        end
      end
    end

    private def iterate_csv_stream(csv_stream, &)
      row_count = 0
      while csv_stream.next
        row_count += 1
        if 0 < @offset
          if row_count < @offset
            next
          elsif row_count == @offset
            puts "Continuing after  #{row_count.format(delimiter: '_')} rows"
            next
          end
        end
        csv_row = csv_stream.row
        sql_row = @sql_field_mapping.map do |mapping|
          csv_value =
            if mapping.csv.nil?
              mapping.value || ""
            else
              csv_row[mapping.csv.not_nil!]
            end
          if csv_value.nil?
            nil
          elsif csv_value.strip == ""
            nil
          else
            csv_value.strip
          end
        end
        post_process = yield(sql_row, csv_row)
        if (row_count % 1000) == 0
          puts "Uploaded #{row_count.format(delimiter: '_')} rows"
        end
        if !post_process.nil?
          post_process.call
        end
      end
      puts "Wrote #{row_count} rows"
    end

    # Mappings for a configuration, where every field is present.
    # Nil records the intention of not using an sql field
    # or not using a csv field.
    record ConfigFieldMapping, sql : String?, csv : String? do
      include JSON::Serializable
    end

    # Mapping for SQL where only sql fields that map to an actual csv
    class SqlFieldMapping
      property sql : String
      property csv : String?
      property value : String?

      # Custom exception for invalid initialization
      class InitializationError < Exception; end

      def initialize(sql : String?, csv : String? = nil, value : String? = nil)
        if (sql.nil?)
          raise InitializationError.new("sql can not be nil")
        end

        @sql = sql.not_nil!
        @csv = csv
        @value = value

        # Ensure exactly one of csv or value is set
        if (csv.nil? && value.nil?) || (!csv.nil? && !value.nil?)
          raise InitializationError.new("Either csv xor value must be set, but not both.")
        end
      end

      def self.from_config_field_mapping(config_mapping : ConfigFieldMapping) : SqlFieldMapping?
        value : String | Nil = nil
        csv = config_mapping.csv

        if csv && /^'(.+)'$/ =~ csv
          value = $1
          csv = nil
        end

        sql = config_mapping.sql
        SqlFieldMapping.new(sql, csv: csv, value: value)
      end

      def to_config_field_mapping : ConfigFieldMapping
        # Escape single quotes in value if present
        escaped_value = value.try &.gsub("'", "''")

        # Check if there's an escaped value and format it as a quoted string if present
        csv_or_value = if escaped_value
                         "'#{escaped_value}'"
                       else
                         csv
                       end

        ConfigFieldMapping.new(sql: sql, csv: csv_or_value)
      end
    end
  end
end
