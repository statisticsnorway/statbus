using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Services.DataSources.Parsers;

namespace nscreg.Services.DataSources
{
    public class HandleQueueItem
    {
        private readonly StatUnitTypes _type;
        private readonly DataSourceAllowedOperation _operation;
        private readonly DataSourcePriority _priority;
        private readonly string _mapping;
        private readonly string _restrictions;
        private readonly IEnumerable<Dictionary<string, string>> _rawEntities;

        private HandleQueueItem(
            StatUnitTypes type,
            DataSourceAllowedOperation operation,
            DataSourcePriority priority,
            string mapping,
            string restrictions,
            IEnumerable<Dictionary<string, string>> rawEntities)
        {
            _type = type;
            _operation = operation;
            _priority = priority;
            _mapping = mapping;
            _restrictions = restrictions;
            _rawEntities = rawEntities;
        }

        public static async Task<HandleQueueItem> CreateXmlHandler(
            string filePath,
            StatUnitTypes type,
            DataSourceAllowedOperation operation,
            DataSourcePriority priority,
            string mapping,
            string restrictions)
        {
            var xdoc = await XmlHelpers.LoadFile(filePath);
            var rawEntities = XmlHelpers.GetRawEntities(xdoc).Select(XmlHelpers.ParseRawEntity);
            return new HandleQueueItem(
                type,
                operation,
                priority,
                mapping,
                restrictions,
                rawEntities);
        }

        public static async Task<HandleQueueItem> CreateCsvHandler(
            string filePath,
            StatUnitTypes type,
            DataSourceAllowedOperation operation,
            DataSourcePriority priority,
            string mapping,
            string restrictions)
        {
            var rawLines = await CsvHelpers.LoadFile(filePath);
            var propNames = CsvHelpers.GetPropNames(rawLines);
            var rawEntities = CsvHelpers.GetParsedEntities(rawLines.Skip(propNames.Item1), propNames.Item2);
            return new HandleQueueItem(
                type,
                operation,
                priority,
                mapping,
                restrictions,
                rawEntities);
        }
    }
}
