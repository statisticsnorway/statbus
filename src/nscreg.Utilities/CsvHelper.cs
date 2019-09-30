using System.Collections.Generic;
using System.Linq;
using System.Text;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Utilities
{
    public class CsvHelper
    {
        private const string Delimiter = ",";
        private readonly LocalizationProvider _localizationProvider;

        public CsvHelper()
        {
            _localizationProvider = new LocalizationProvider();
        }

        public string ConvertToCsv(IEnumerable<IReadOnlyDictionary<FieldEnum, string>> items, bool withHeaders = true)
        {
            var buffer = new StringBuilder();
            var isFirst = true;
            foreach (var item in items)
            {
                if (isFirst && withHeaders)
                {
                    WriteHeader(item, buffer);
                    isFirst = false;
                }
                WriteItem(item, buffer);
            }
            return buffer.ToString();
        }

        private void WriteItem(IReadOnlyDictionary<FieldEnum, string> item, StringBuilder buffer)
        {
            var list = item.Values.Select(x => $"\"{ProcessStringEscapeSequence(x ?? string.Empty)}\"");
            buffer.AppendLine(CreateCsvLine(list));
        }

        private void WriteHeader(IReadOnlyDictionary<FieldEnum, string> item, StringBuilder buffer)
        {
            if (item == null)
                return;
            var fields = item.Keys.Select(x=> _localizationProvider.GetString(x.ToString()));
            var line = CreateCsvLine(fields);
            buffer.AppendLine(line);
        }

        private static string CreateCsvLine(IEnumerable<string> fields)
        {
            return string.Join(Delimiter, fields);
        }

        private string ProcessStringEscapeSequence(string value)
        {
            return value.Replace("\"", "\"\"");
        }
    }
}
