# Run with
#     crystal norway-sample-regions.cr
require "http/client"
require "csv"

enum FileType
  Fylker
  Kommuner
end

struct FileData
  property url : String
  property file_type : FileType

  def initialize(@url : String, @file_type : FileType)
  end
end

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

def print_file_head(filepath : String)
  puts "Head of the file #{filepath}:"
  File.open(filepath) do |file|
    10.times do
      line = file.gets
      break unless line
      puts line
    end
  end
rescue ex
  puts "Error opening file #{filepath} for head printing: #{ex.message}"
end

def process_csv(filepath : String, file_type : FileType, csv_builder : CSV::Builder)
  file_content = File.read(filepath)
  csv_content = CSV.parse(file_content, ';')

  csv_content.each_with_index do |row, index|
    next if index == 0 # Skip header

    if row.size < 4
      puts "Skipping invalid record in file #{filepath} on line #{index + 1}: #{row}"
      next
    end

    data = case file_type
           when FileType::Fylker
             [row[0], row[3]]
           when FileType::Kommuner
             [row[0].insert(2, '.'), row[3]]
           else
             raise "Unknown file type for file #{filepath}"
           end

    csv_builder.row(data)
  end
rescue ex
  puts "Error processing file #{filepath}: #{ex.message}"
end

files = [
  FileData.new(url: "https://data.ssb.no/api/klass/v1//versions/1709.csv?language=nb", file_type: FileType::Fylker),
  FileData.new(url: "https://data.ssb.no/api/klass/v1//versions/1710.csv?language=nb", file_type: FileType::Kommuner),
]

csv_data = CSV.build do |csv_builder|
  files.each do |f|
    filename = f.url.split('/').last.split('?').first

    downloaded_filename = download_file_if_not_exist(f.url, filename)
    if downloaded_filename
      begin
        process_csv(downloaded_filename, f.file_type, csv_builder)
      rescue ex
        puts "Error during CSV processing: #{ex.message}"
      end
    end
  end
end
File.write("norway-sample-regions.csv", csv_data)
