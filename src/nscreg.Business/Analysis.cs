using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Business
{
    public static class Analysis
    {
        public static IEnumerable<KeyValuePair<string, string>> Analyze(IStatisticalUnit unit)
        {
            var errors = new Dictionary<string, string>();
            if (string.IsNullOrEmpty(unit.StatId)) errors.Add(nameof(unit.StatId), "Value is required");
            return errors;
        }
    }
}
