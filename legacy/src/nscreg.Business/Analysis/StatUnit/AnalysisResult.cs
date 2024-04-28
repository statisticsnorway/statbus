using System.Collections.Generic;
using nscreg.Data.Constants;

namespace nscreg.Business.Analysis.StatUnit
{
    public class AnalysisResult
    {
        public string Name { get; set; }

        public StatUnitTypes Type { get; set; }

        public Dictionary<string, string[]> Messages { get; set; }

        public List<string> SummaryMessages { get; set; }
    }
}
