using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Services.DataSources.Parsers;

namespace nscreg.Services.DataSources
{
    public static class FileParser
    {
        public static async Task<IEnumerable<IReadOnlyDictionary<string, string>>>
            GetRawEntitiesFromXml(string filePath)
            => XmlHelpers.GetRawEntities(await XmlHelpers.LoadFile(filePath)).Select(XmlHelpers.ParseRawEntity);

        public static async Task<IEnumerable<IReadOnlyDictionary<string, string>>>
            GetRawEntitiesFromCsv(string filePath)
        {
            var rawLines = await CsvHelpers.LoadFile(filePath);
            var (count, propNames) = CsvHelpers.GetPropNames(rawLines);
            return CsvHelpers.GetParsedEntities(rawLines.Skip(count), propNames);
        }
    }
}
