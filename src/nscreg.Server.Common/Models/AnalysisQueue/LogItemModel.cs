using System;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class LogItemModel
    {
        public int Id { get; set; }
        public int UnitId { get; set; }
        public string UnitName { get; set; }
        public string UnitType { get; set; }
        public DateTimeOffset IssuedAt { get; set; }
        public DateTimeOffset? ResolvedAt { get; set; }
        public string[] SummaryMessages { get; set; }
    }
}
