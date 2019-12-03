using System.Collections.Generic;
using System.Linq;

namespace nscreg.Utilities
{
    /// <summary>
    /// Data source variable mapping class
    /// </summary>
    public static class DataSourceVariableMappingHelper
    {
        /// <summary>
        /// Method to convert a string to a dictionary
        /// </summary>
        /// <param name = "variablesMapping"> Variable mapping </param>
        /// <returns> </returns>
        public static IReadOnlyDictionary<string, string> ParseStringToDictionary(string variablesMapping)
            => variablesMapping
                .Split(',')
                .ToDictionary(
                    x => x.Split('-')[0],
                    x => x.Split('-')[1]);
    }
}
