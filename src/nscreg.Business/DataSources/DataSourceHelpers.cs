using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;

namespace nscreg.Business.DataSources
{
    public static class DataSourceHelpers
    {
        public static string StatIdSourceKey(IEnumerable<(string source, string target)> variablesMapping)
            => variablesMapping.SingleOrDefault(vm => vm.target == nameof(IStatisticalUnit.StatId)).source;
    }
}
