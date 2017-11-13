using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Linq;
using nscreg.Business.DataSources;

namespace nscreg.Server.Common.Services.DataSources
{
    public static class FileParser
    {
        public static IEnumerable<IReadOnlyDictionary<string, string>> GetRawEntitiesFromXml(string filePath)
            => XmlParser.GetRawEntities(XDocument.Load(filePath)).Select(XmlParser.ParseRawEntity);

        public static async Task<IEnumerable<IReadOnlyDictionary<string, string>>> GetRawEntitiesFromCsv(
            string filePath, int skipCount, string delimiter)
        {
            var i = skipCount;
            string rawLines;
            using (var stream = File.OpenRead(filePath))
            using (var reader = new StreamReader(stream))
            {
                while (--i == 0) await reader.ReadLineAsync();
                rawLines = await reader.ReadToEndAsync();
            }

            return CsvParser.GetParsedEntities(rawLines, delimiter);
        }
    }
}
