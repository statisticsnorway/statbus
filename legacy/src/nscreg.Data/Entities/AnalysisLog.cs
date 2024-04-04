using System;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Entity Log Analysis Class
    /// </summary>
    public class AnalysisLog
    {
        public int Id { get; set; }
        public int AnalysisQueueId { get; set; }
        public int AnalyzedUnitId { get; set; }
        public StatUnitTypes AnalyzedUnitType { get; set; }
        public DateTimeOffset IssuedAt { get; set; }
        public DateTimeOffset? ResolvedAt { get; set; }
        public string SummaryMessages { get; set; }
        public string ErrorValues { get; set; }

        public virtual AnalysisQueue AnalysisQueue { get; set; }
    }
}
