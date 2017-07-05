using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Linq;
using nscreg.Business.DataSources;

namespace nscreg.Services.DataSources
{
    public static class FileParser
    {
        public static IEnumerable<IReadOnlyDictionary<string, string>>
            GetRawEntitiesFromXml(string filePath)
            => XmlParser.GetRawEntities(XDocument.Load(filePath)).Select(XmlParser.ParseRawEntity);

        public static async Task<IEnumerable<IReadOnlyDictionary<string, string>>>
            GetRawEntitiesFromCsv(string filePath)
        {
            var rawLines = new List<string>();

            using (var stream = File.OpenRead(filePath))
            using (var reader = new StreamReader(stream))
                while (!reader.EndOfStream)
                    rawLines.Add(await reader.ReadLineAsync());

            var (count, propNames) = CsvParser.GetPropNames(rawLines);
            return CsvParser.GetParsedEntities(rawLines.Skip(count), propNames);
        }
    }
}
