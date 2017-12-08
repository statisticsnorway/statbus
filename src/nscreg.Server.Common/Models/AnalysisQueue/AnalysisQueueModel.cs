using System;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class AnalysisQueueModel
    {
        public int Id { get; set; }
        public DateTime UserStartPeriod { get; set; }
        public DateTime UserEndPeriod { get; set; }
        public string UserName { get; set; }
        public string Comment { get; set; }
        public DateTime? ServerStartPeriod { get; set; }
        public DateTime? ServerEndPeriod { get; set; }
    }
}
