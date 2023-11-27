# Helper to produce isic v4
# Presumes files downloaded from
# "https://unstats.un.org/unsd/classifications/Econ/Download/In%20Text/ISIC_Rev_4_english_structure.Txt"
# and creates a csv suitable for input to
# our project using ltree path with custom insert function.
#
# Run with
#   crystal ISIC_Rev_4_english_structure.cr
# in the same directory as "ISIC_Rev_4_english_structure.Txt"
# to produce the csv file.
#

require "file"
require "csv"

inputFileName = "ISIC_Rev_4_english_structure.Txt"
outputFileName = "ISIC_Rev_4_english_structure.csv"

inputFile = File.read inputFileName
lines = CSV.parse(inputFile, ',', '"')[1...]

prefix = [] of String
path = [] of String
output = CSV.build(quoting: CSV::Builder::Quoting::ALL) do |csv|
  lines.each do |line|
    code, description = line
    level = code.size
    case level
    when 1 # A new major section
      prefix = [code]
      path = prefix
    when 2
      if prefix.size == 1
        prefix = prefix + [code]
      else
        prefix = prefix[0..-1]
      end
      path = prefix
    when 3
      relativeCode = code[2...]
      if prefix.size == 3
        # If the prefix is from a previous level 3,
        # then replace the last part with this.
        prefix = prefix[0...-1]
      end
      prefix = prefix + [relativeCode]
      path = prefix
    when 4
      relativeCode = code[3...]
      path = prefix + [relativeCode]
    else
      puts "Unexpected formatting"
    end
    label = path.join(".")
    puts "code #{code} label #{label} description #{description}"
    csv.row label, description
  end
end
File.write outputFileName, output
