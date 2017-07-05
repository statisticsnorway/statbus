using System;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Business.DataSources
{
    public static class CsvParser
    {
        public static IEnumerable<IReadOnlyDictionary<string, string>> GetParsedEntities(
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
