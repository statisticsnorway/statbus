# Helper to produce Norwegian NACE activity category codes suitable for Statbus
# Presumes file downloaded from
# "https://data.ssb.no/api/klass/v1//versions/30.csv?language=nb"
# Via the web interface at "https://www.ssb.no/klass/klassifikasjoner/6"
#
# Read the csv and creates suitable input to our project using ltree path.
# The extra information provided in separate columns is inserted into the
# `description` field as markdown data.
#
# Run with
#   crystal activity_category_norway.cr
# in the same directory as "30.csv"
# to produce the csv file.
#

require "file"
require "csv"
require "http/client"

inputFileName = "30.csv"
outputFileName = "activity_category_norway.csv"

def download_file_if_not_exist(url : String, filepath : String) : String
  return filepath if File.exists?(filepath)

  HTTP::Client.get(url) do |response|
    File.open(filepath, "w") do |file|
      # Instead of using IO#copy, then iterate over each line,
      # to ensure that the encoding of the response (latin-1)
      # is changed to UTF-8 (the default for a new file.).
      response.body_io.each_line do |line|
        file.puts line
      end
    end
  end

  filepath
rescue ex
  raise "Failed to download or save file: #{ex.message}"
end

download_file_if_not_exist("https://data.ssb.no/api/klass/v1//versions/30.csv?language=nb", inputFileName)

alias NaceRow = NamedTuple(
  code: String,
  parentCode: String?,
  level: Int32,
  name: String,
  shortName: String,
  notes: String)

alias ActivityCategoryRow = NamedTuple(
  path: Array(String),
  name: String,
  description: String,
)

inputRows = [] of NaceRow
outputRows = [] of ActivityCategoryRow

parents = {} of String => {level: Int32, code: String, parentCode: String?}

inputFile = File.read inputFileName
lines = CSV.parse(inputFile, ';', '"')[1...]

lines.each do |line|
  code, parentCode, level, name, shortName, notes = line
  level = level.to_i
  parentCode = parentCode.empty? ? nil : parentCode

  inputRow = NaceRow.new(code: code, parentCode: parentCode, level: level, name: name, shortName: shortName, notes: notes)
  inputRows << inputRow
  # puts "#{inputRow[:parentCode]} #{inputRow[:code]} #{inputRow[:level]}"
end

inputRows.each do |inputRow|
  code = inputRow[:code]
  parents[code] = {
    level:      inputRow[:level],
    code:       inputRow[:code],
    parentCode: inputRow[:parentCode],
  }
  # puts "#{parents[code]}"
end

paths = {} of String => Array(String)

def get_short_code(code : String, parentCode : String?)
  if parentCode && code.starts_with?(parentCode)
    code[parentCode.size..]
  else
    code
  end.sub(".", "")
end

parents.each do |code, details|
  original_code = code # Store the original code
  # puts "#{original_code}"
  path = [] of String

  while code
    parent_details = parents[code]
    if parent_details
      parentCode = parent_details[:parentCode]
      short_code = get_short_code(code, parentCode)
      # puts "code #{code} ~ short_code #{short_code}"
      path.unshift(short_code) # prepend the short_code to the path
      code = parentCode        # Move to the next parent
    else
      break # No more parents, exit the loop
    end
  end

  paths[original_code] = path
  # puts "#{original_code}->#{path.join(".")}"
end

inputRows.each do |inputRow|
  code = inputRow[:code]
  path = paths[code] || [] of String
  name = inputRow[:name]

  # Constructing markdown formatted description
  description = "### Shortname: #{inputRow[:shortName]}\n\n"
  description += "### Notes:\n#{inputRow[:notes]}\n\n" unless inputRow[:notes].empty?

  outputRow = {
    path:        path,
    name:        name,
    description: description.strip, # Removes any trailing newline characters
  }
  outputRows << outputRow
  # puts outputRow
end

outputRows = outputRows.sort { |a, b| a[:path] <=> b[:path] }

output = CSV.build(quoting: CSV::Builder::Quoting::ALL) do |csv|
  csv.row ["path", "name", "description"]
  outputRows.each do |row|
    path = row[:path].join(".")
    name = row[:name]
    description = row[:description]

    # puts "path #{path} name #{name} description #{description}"
    csv.row path, name, description
  end
end

File.write outputFileName, output
