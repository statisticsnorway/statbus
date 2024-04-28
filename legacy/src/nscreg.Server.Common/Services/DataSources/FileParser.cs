using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
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
            string filePath, (string source, string target)[] mappings, int skipCount)
        {
            using (var fileStream = File.OpenRead(filePath))
            {
                return XmlParser.GetRawEntities(await XDocument.LoadAsync(fileStream, LoadOptions.None, CancellationToken.None))
                    .Select(x => XmlParser.ParseRawEntity(x, mappings, skipCount));
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
            string filePath, string delimiter, (string source, string target)[]  variableMappings, int skipLines)
        {
            string rawLines;
            using (FileStream fs = File.Open(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (BufferedStream bs = new BufferedStream(fs, 4096*4))
            using (StreamReader reader = new StreamReader(bs, encoding: Encoding.UTF8))
            {
                rawLines = await reader.ReadLineAsync();

                for(int i = 0; i < skipLines; ++i)
                    await reader.ReadLineAsync();

                rawLines += $"\n{await reader.ReadToEndAsync()}";
            }
            ///We make a Replace because this symbol " is problematic in the library ServiceStack.Text
            return CsvParser.GetParsedEntities(rawLines.Replace("\"", ""), delimiter, variableMappings);
        }
    }
}
