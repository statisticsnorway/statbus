using System;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class LogItemModel
    {
        public int Id { get; set; }
        public int UnitId { get; set; }
        public string UnitName { get; set; }
        public string UnitType { get; set; }
        public DateTime IssuedAt { get; set; }
        public DateTime? ResolvedAt { get; set; }
        public string[] SummaryMessages { get; set; }
    }
}
