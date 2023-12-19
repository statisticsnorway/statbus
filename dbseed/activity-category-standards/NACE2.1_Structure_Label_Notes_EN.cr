# Helper to produce NACE v2.1
# Presumes file downloaded from
# "https://showvoc.op.europa.eu/semanticturkey/it.uniroma2.art.semanticturkey/st-core-services/Storage/getFile?path=proj%3A%2Fdownload%2FNACE2.1_Structure_Label_Notes_EN.csv&ctx_project=ESTAT_Statistical_Classification_of_Economic_Activities_in_the_European_Community_Rev._2.1._(NACE_2.1)&"
# Via the web interface at https://showvoc.op.europa.eu/#/datasets/ESTAT_Statistical_Classification_of_Economic_Activities_in_the_European_Community_Rev._2.1._%28NACE_2.1%29
# under the "Metadata" tab.
# Read the csv and creates suitable input to our project using ltree path.
# The extra information provided in separate columns is inserted into the
# `description` field as markdown data.
#
# Run with
#   crystal NACE2.1_Structure_Label_Notes_EN.cr
# in the same directory as "NACE2.1_Structure_Label_Notes_EN.csv"
# to produce the csv file.
#

require "file"
require "csv"

inputFileName = "NACE2.1_Structure_Label_Notes_EN.csv"
outputFileName = "NACE2.1_Structure_Label_Notes_EN.import.csv"

alias NaceRow = NamedTuple(
  uri: String,
  identifier: String,
  parent_identifier: String?,
  nace_code: String,
  parent_code: String,
  name: String,
  level: String,
  level_depth: Int32,
  includes: String,
  includes_also: String,
  excludes: String,
  case_law_if_applicable: String)

alias ActivityCategoryRow = NamedTuple(
  path: Array(String),
  name: String,
  description: String,
)

inputRows = [] of NaceRow
outputRows = [] of ActivityCategoryRow

parents = {} of String => {level: String, identifier: String, parent_identifier: String?}

inputFile = File.read inputFileName
lines = CSV.parse(inputFile, ',', '"')[1...]

lines.each do |line|
  uri, identifier, parent_identifier, nace_code, parent_code, name, level, level_depth, includes, includes_also, excludes, case_law_if_applicable = line
  level_depth = level_depth.to_i
  parent_identifier = parent_identifier.empty? ? nil : parent_identifier

  inputRow = {
    uri:                    uri,
    identifier:             identifier,
    parent_identifier:      parent_identifier,
    nace_code:              nace_code,
    parent_code:            parent_code,
    name:                   name,
    level:                  level,
    level_depth:            level_depth,
    includes:               includes,
    includes_also:          includes_also,
    excludes:               excludes,
    case_law_if_applicable: case_law_if_applicable,
  }
  inputRows << inputRow
  # puts "#{inputRow[:parent_identifier]} #{inputRow[:identifier]} #{inputRow[:nace_code]}  #{inputRow[:level]}"
end

inputRows.each do |inputRow|
  identifier = inputRow[:identifier]
  parents[identifier] = {
    level:             inputRow[:level],
    identifier:        inputRow[:identifier],
    parent_identifier: inputRow[:parent_identifier],
  }
  # puts "#{parents[identifier]}"
end

paths = {} of String => Array(String)

def get_short_identifier(identifier : String, parent_identifier : String?)
  if parent_identifier && identifier.starts_with?(parent_identifier)
    identifier[parent_identifier.size..]
  else
    identifier
  end
end

parents.each do |identifier, details|
  original_identifier = identifier # Store the original identifier
  path = [] of String

  while identifier
    parent_details = parents[identifier]
    if parent_details
      parent_identifier = parent_details[:parent_identifier]
      short_identifier = get_short_identifier(identifier, parent_identifier)
      path.unshift(short_identifier) # prepend the short_identifier to the path
      identifier = parent_identifier # Move to the next parent
    else
      break # No more parents, exit the loop
    end
  end

  paths[original_identifier] = path
  # puts "#{original_identifier}->#{path.join(".")}"
end

inputRows.each do |inputRow|
  identifier = inputRow[:identifier]
  path = paths[identifier] || [] of String
  nace_code = inputRow[:nace_code]

  # Remove the nace_code prefix from the name
  nace_code_prefix = "#{nace_code} "
  if inputRow[:name].starts_with?(nace_code_prefix)
    name = inputRow[:name][nace_code_prefix.size..]
  else
    name = inputRow[:name]
  end

  # Constructing markdown formatted description
  description = "### NACE Code: #{inputRow[:nace_code]}\n\n"
  description += "#### Includes:\n#{inputRow[:includes]}\n\n" unless inputRow[:includes].empty?
  description += "#### Includes Also:\n#{inputRow[:includes_also]}\n\n" unless inputRow[:includes_also].empty?
  description += "#### Excludes:\n#{inputRow[:excludes]}\n\n" unless inputRow[:excludes].empty?
  description += "#### Case Law (If Applicable):\n#{inputRow[:case_law_if_applicable]}\n\n" unless inputRow[:case_law_if_applicable].empty?

  outputRow = {
    path:        path,
    name:        name,
    description: description.strip, # Removes any trailing newline characters
  }
  outputRows << outputRow
  # puts outputRow
end

output = CSV.build(quoting: CSV::Builder::Quoting::ALL) do |csv|
  outputRows.each do |row|
    path = row[:path]
    name = row[:name]
    description = row[:description]

    # Constructing the label from the path
    label = path.join(".")

    # puts "label #{label} name #{name} description #{description}"
    csv.row label, name, description
  end
end

File.write outputFileName, output
