# This Crystal script is designed to process data from the Norwegian Statistics Bureau (SSB)
# "sektorkode" classification system. The script downloads a CSV file from the SSB API,
# processes the data to conform to a specific structure, and outputs a new CSV file prepared for the
# legal_form table in a database.
#
# The script extracts the fields "code" and "name" into a suitable csv file.
# It employs the Crystal programming language's CSV and
# HTTP client capabilities for downloading and processing the CSV data.
#
# Usage:
# - Ensure Crystal is installed on your system.
# - Place this script in a directory of your choice.
# - Run the script using `crystal <script_name>.cr`.
# - The script will download the required CSV file from the provided SSB URL,
#   process the data, and output a new CSV file in the same directory.
#

require "file"
require "csv"
require "http/client"
require "time"

outputFileName = "legal_form_norway.csv"
dataSourceUrl = "https://data.ssb.no/api/klass/v1/versions/1544.csv?language=nb"
tempFileName = "ssb_legal_form.csv"

outputFilePath = File.join(__DIR__, outputFileName)
tempFilePath = File.join(Dir.tempdir, tempFileName)

def download_file_if_needed(url : String, filepath : String)
  if File.exists?(filepath)
    file_modification_time = File.info(filepath).modification_time
    file_age_days = (Time.utc - file_modification_time).total_seconds / 86400
    if file_age_days > 7
      puts "Existing file '#{filepath}' is older than 7 days. Downloading new file..."
    else
      puts "Existing file '#{filepath}' is up-to-date. Using existing file for processing."
      return
    end
  else
    puts "Temporary file does not exist. Downloading now..."
  end

  HTTP::Client.get(url) do |response|
    File.open(filepath, "w") do |file|
      response.body_io.each_line do |line|
        file.puts line
      end
    end
  end
  puts "File downloaded and stored at '#{filepath}' for inspection."
end

puts "Starting script execution..."
download_file_if_needed(dataSourceUrl, tempFilePath)

alias LegalFormRow = NamedTuple(
  code: String,
  name: String,
)

rows = [] of LegalFormRow

puts "Reading and parsing the input file '#{tempFilePath}'..."
inputFile = File.read tempFilePath
CSV.new(inputFile, headers: true, separator: ';', quote_char: '"') do |line|
  row = {code: line["code"], name: line["name"]}
  rows << row
end
puts "Input file parsing and row processing completed. Total rows processed: #{rows.size}"

rows.sort_by! { |row| row[:code] }

puts "Writing to output file '#{outputFilePath}'..."
File.open(outputFilePath, "w") do |file|
  CSV.build(file, quoting: CSV::Builder::Quoting::ALL) do |csv|
    csv.row ["code", "name"]
    rows.each do |row|
      csv.row [row[:code], row[:name]]
    end
  end
end
puts "Output file '#{outputFilePath}' written successfully."
puts "Script execution completed. Temporary file available at '#{tempFilePath}' for inspection."
