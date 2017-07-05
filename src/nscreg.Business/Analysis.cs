using System;
using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Business
{
    public static class Analysis
    {
        public static IEnumerable<KeyValuePair<string, string>> Analyze(IStatisticalUnit unit)
            => Array.Empty<KeyValuePair<string, string>>();
    }
}
