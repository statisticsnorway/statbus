using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit.Analyzers
{
    public interface IEnterpriseUnitAnalyzer
    {
        Dictionary<string, string[]> CheckOrphanUnits(IStatisticalUnit unit);
    }
}