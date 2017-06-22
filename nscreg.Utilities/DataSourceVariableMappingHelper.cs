using System.Collections.Generic;
using System.Linq;

namespace nscreg.Utilities
{
    public static class DataSourceVariableMappingHelper
    {
        public static IReadOnlyDictionary<string, string> ParseStringToDictionary(string variablesMapping)
            => variablesMapping
                .Split(',')
                .ToDictionary(
                    x => x.Split('-')[0],
                    x => x.Split('-')[1]);
    }
}
