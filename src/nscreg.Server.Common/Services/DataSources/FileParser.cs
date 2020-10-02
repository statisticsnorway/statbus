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
        public static async Task GetRawEntitiesFromXml(
            string filePath, (string source, string target)[] mappings, System.Collections.Concurrent.BlockingCollection<IReadOnlyDictionary<string, object>> tasks)
        {
            using (var fileStream = File.OpenRead(filePath))
            {
                foreach(var x in XmlParser.GetRawEntities(await XDocument.LoadAsync(fileStream, LoadOptions.None, CancellationToken.None)))
                    tasks.Add(XmlParser.ParseRawEntity(x, mappings));
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
        public static async Task GetRawEntitiesFromCsv(
            string filePath, int skipCount, string delimiter, (string source, string target)[]  variableMappings, System.Collections.Concurrent.BlockingCollection<IReadOnlyDictionary<string, object>> tasks)
        {
            var i = skipCount;
            string rawLines;
            using (var stream = File.OpenRead(filePath))
            using (var reader = new StreamReader(stream))
            {
                while (--i == 0) await reader.ReadLineAsync();
                rawLines = await reader.ReadToEndAsync();
            }

            CsvParser.GetParsedEntities(rawLines, delimiter, variableMappings, tasks);
        }
    }
}
