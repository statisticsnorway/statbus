using System;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class AnalysisQueueModel
    {
        public int Id { get; set; }
        public DateTimeOffset UserStartPeriod { get; set; }
        public DateTimeOffset UserEndPeriod { get; set; }
        public string UserName { get; set; }
        public string Comment { get; set; }
        public DateTimeOffset? ServerStartPeriod { get; set; }
        public DateTimeOffset? ServerEndPeriod { get; set; }
    }
}
