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

path = [] of String
output = CSV.build(quoting: CSV::Builder::Quoting::ALL) do |csv|
  lines.each do |line|
    code, description = line
    level = code.size
    case level
    when 1 # A new major section
      #   "A","Agriculture, forestry and fishing"
      # path = ["A"]
      path = [code]
    when 2
      if path.size == 1
        #   "A","Agriculture, forestry and fishing"
        # path = ["A"]
        #   "01","Crop and animal production, hunting and related service activities"
        # path = ["A","01"]
        path = path + [code]
      else
        #   "0170","Hunting, trapping and related service activities"
        # path = ["A","01","7","1"]
        #   "02","Forestry and logging"
        # path = ["A","02"]
        path = path[0..0] + [code]
      end
    when 3
      relativeCode = code[2...]
      if path.size > 3
        #   "0119","Growing of other non-perennial crops"
        # path = ["A","01","1","9"]
        #   "012","Growing of perennial crops"
        # path = ["A","01","2"]
        path = path[0..1] + [relativeCode]
      else
        #   "01","Crop and animal production, hunting and related service activities"
        # path = ["A","01"]
        #   "011","Growing of non-perennial crops"
        # path = ["A","01","1"]
        path = path + [relativeCode]
      end
    when 4
      relativeCode = code[3...]
      if path.size == 4
        #   "0111","Growing of cereals (except rice), leguminous crops and oil seeds"
        # path = ["A","01","1","1"]
        #   "0112","Growing of rice"
        # path = ["A","01","1","2"]
        path = path[0..2] + [relativeCode]
      else
        #   "011","Growing of non-perennial crops"
        # path = ["A","01","1"]
        #   "0111","Growing of cereals (except rice), leguminous crops and oil seeds"
        # path = ["A","01","1","1"]
        path = path + [relativeCode]
      end
    else
      puts "Unexpected formatting"
    end
    label = path.join(".")
    puts "code #{code} label #{label} description #{description}"
    csv.row label, description
  end
end
File.write outputFileName, output
