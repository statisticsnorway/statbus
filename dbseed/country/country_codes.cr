require "http/client"
require "csv"
require "xml"

# Download official country codes and put the in a csv file for db import.
module CountryCodes
  VERSION = "0.1.0"

  url = "https://www.iban.com/country-codes"
  response = HTTP::Client.get(url)
  unless response.status_code == 200
    raise "Failed to download the page"
  end

  doc = XML.parse_html(response.body)

  outputFileName = "country_codes.csv"
  output = CSV.build do |csv|
    csv.row "Country", "Alpha-2 code", "Alpha-3 code", "Numeric"
    doc.xpath_nodes("//table[@id='myTable']/tbody/tr").each do |row|
      cells = row.xpath_nodes("td").map(&.text.strip)
      csv.row cells
    end
  end

  File.write outputFileName, output

  puts "Country codes have been saved to #{outputFileName}"
end
