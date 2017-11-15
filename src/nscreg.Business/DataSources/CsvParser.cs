using ServiceStack;
using System.Collections.Generic;
using ServiceStack.Text;

namespace nscreg.Business.DataSources
{
    public static class CsvParser
    {
        public static IEnumerable<IReadOnlyDictionary<string, string>> GetParsedEntities(string rawLines, string delimiter)
        {
            CsvConfig.ItemSeperatorString = delimiter;
            return rawLines.FromCsv<List<Dictionary<string, string>>>();
        }
    }
}
