# This Crystal script is designed to process data from the Norwegian Statistics Bureau (SSB)
# "institusjonellSektorkode" classification system. The script downloads a CSV file from the SSB API,
# processes the data to conform to a specific structure, and outputs a new CSV file prepared for the
# sector_code table in a database.
#
# The script handles specific fields such as 'code', 'parentCode', 'level', 'name', and 'notes', translating
# them into a format suitable for database insertion. It employs the Crystal programming language's CSV and
# HTTP client capabilities for downloading and processing the CSV data.
#
# Usage:
# - Ensure Crystal is installed on your system.
# - Place this script in a directory of your choice.
# - Run the script using `crystal <script_name>.cr`.
# - The script will download the required CSV file from the provided SSB URL, process the data, and output
#   a new CSV file named 'sector_code_table.csv' in the same directory.
#
# Source Data URL: https://data.ssb.no/api/klass/v1/versions/92.csv?language=nb
# The script expects the CSV file to have specific headers as per the 'institusjonellSektorkode' classification.
# The output is tailored for easy integration into a database table that tracks different sectors as per Norwegian
# institutional sector codes.

require "file"
require "csv"
require "http/client"
require "time"

outputFileName = "#{__DIR__}/sector_code_norway.csv"
dataSourceUrl = "https://data.ssb.no/api/klass/v1/versions/92.csv?language=nb"
tempFileName = "ssb_temp.csv" # Name for the temporary file for easier identification
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

alias SectorCodeRow = NamedTuple(
  code: String,
  parentCode: String?,
  level: Int32,
  name: String,
  notes: String?)

alias OutputRow = NamedTuple(
  path: Array(String),
  name: String,
  description: String,
)

inputRows = [] of SectorCodeRow
outputRows = [] of OutputRow
parents = {} of String => {level: Int32, code: String, parentCode: String?}

puts "Reading and parsing the input file '#{tempFilePath}'..."
inputFile = File.read tempFilePath
lines = CSV.parse(inputFile, ';', '"')[1...]
puts "Total rows read from input file: #{lines.size}"

lines.each do |line|
  code, parentCode, level, name, _, notes = line
  level = level.to_i
  parentCode = parentCode.empty? ? nil : parentCode
  notes = notes.strip unless notes.nil?

  inputRow = {code: code, parentCode: parentCode, level: level, name: name, notes: notes}
  inputRows << inputRow
end
puts "Input file parsing and row processing completed. Total rows processed: #{inputRows.size}"

puts "Building hierarchy and paths..."
inputRows.each do |inputRow|
  code = inputRow[:code]
  parents[code] = {
    level:      inputRow[:level],
    code:       inputRow[:code],
    parentCode: inputRow[:parentCode],
  }
end

paths = {} of String => Array(String)

def get_path_part(code : String, parentCode : String?)
  if parentCode && code.starts_with?(parentCode)
    code[parentCode.size..]
  else
    code
  end.sub(".", "").sub("-", "_").downcase
end

parents.each do |code, _|
  original_code = code
  path = [] of String

  while code
    parent_details = parents[code]
    if parent_details
      parentCode = parent_details[:parentCode]
      path_part = get_path_part(code, parentCode)
      path.unshift(path_part)
      code = parentCode
    else
      break
    end
  end

  paths[original_code] = path
end
puts "Hierarchy and paths built. Total unique codes with paths: #{paths.size}"

puts "Generating output rows..."
inputRows.each do |inputRow|
  code = inputRow[:code]
  path = paths[code] || [] of String
  name = inputRow[:name]
  description = ""
  notes = inputRow[:notes].presence
  if !notes.nil?
    description += "### Notes:\n#{notes}"
  end

  outputRow = {
    path:        path,
    name:        name,
    description: description,
  }

  outputRows << outputRow unless description.nil?
end

outputRows = outputRows.sort_by { |row| row[:path].join(".") }

puts "Writing to output file '#{outputFileName}'..."
File.open(outputFileName, "w") do |file|
  CSV.build(file, quoting: CSV::Builder::Quoting::ALL) do |csv|
    csv.row ["path", "name", "description"]
    outputRows.each do |row|
      path = row[:path].join(".")
      csv.row [path, row[:name], row[:description]]
    end
  end
end
puts "Output file '#{outputFileName}' written successfully."
puts "Script execution completed. Temporary file available at '#{tempFilePath}' for inspection."
