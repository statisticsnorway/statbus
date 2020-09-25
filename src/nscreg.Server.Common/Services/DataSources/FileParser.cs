using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Xml.Linq;
using nscreg.Business.DataSources;

namespace nscreg.Server.Common.Services.DataSources
{
    public static class FileParser
    {
        /// <summary>
        /// Method for parse entity from xml file
        /// </summary>
        /// <param name="filePath">file path</param>
        /// <param name="mappings">variable mappings array</param>
        /// <returns></returns>
        public static async Task<IEnumerable<IReadOnlyDictionary<string, object>>> GetRawEntitiesFromXml(
            string filePath, (string source, string target)[] mappings)
        {
            using (var fileStream = File.OpenRead(filePath))
            {
                return XmlParser.GetRawEntities(await XDocument.LoadAsync(fileStream, LoadOptions.None, CancellationToken.None)).Select(x => XmlParser.ParseRawEntity(x ,mappings));
            }
        }

        /// <summary>
        /// Method for parse entity from csv file
        /// </summary>
        /// <param name="filePath"></param>
        /// <param name="skipCount"></param>
        /// <param name="delimiter"></param>
        /// <param name="variableMappings"></param>
        /// <returns></returns>
        public static async Task<IEnumerable<IReadOnlyDictionary<string, object>>> GetRawEntitiesFromCsv(
            string filePath, int skipCount, string delimiter, (string source, string target)[]  variableMappings)
        {
            var i = skipCount;
            string rawLines;
            using (var stream = File.OpenRead(filePath))
            using (var reader = new StreamReader(stream))
            {
                while (--i == 0) await reader.ReadLineAsync();
                rawLines = await reader.ReadToEndAsync();
            }

            return CsvParser.GetParsedEntities(rawLines, delimiter, variableMappings);
        }
    }
}
