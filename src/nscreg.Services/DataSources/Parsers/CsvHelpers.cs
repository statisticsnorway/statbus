using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Services.DataSources.Parsers
{
    public static class CsvHelpers
    {
        public static async Task<List<string>> LoadFile(string filePath)
        {
            using (var stream = File.OpenRead(filePath))
            using (var reader = new StreamReader(stream))
            {
                var rawLines = new List<string>();
                while (!reader.EndOfStream) rawLines.Add(await reader.ReadLineAsync());
                return rawLines;
            }
        }

        public static IEnumerable<Dictionary<string, string>> GetParsedEntities(
            IEnumerable<string> rawEntities,
            string[] propNames)
            => rawEntities
                .Select(props =>
                {
                    var result = new Dictionary<string, string>();
                    var rawPropsArr = props.Split(',');
                    for (var i = 0; i < rawPropsArr.Length; i++)
                        result.Add(propNames[i], rawPropsArr[i]);
                    return result;
                });

        public static (int count, string[] propNames) GetPropNames(IList<string> rawLines)
        {
            for (var i = 0; i < rawLines.Count; i++)
                if (rawLines[i].Contains(','))
                    return (i, rawLines[i].Split(','));
            return (0, Array.Empty<string>());
        }
    }
}
