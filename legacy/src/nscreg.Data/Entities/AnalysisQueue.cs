using System;
using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    public class AnalysisQueue
    {
        public int Id { get; set; }
        public DateTimeOffset UserStartPeriod { get; set; }
        public DateTimeOffset UserEndPeriod { get; set; }
        public string UserId { get; set; }
        public string Comment { get; set; }

        public DateTimeOffset? ServerStartPeriod { get; set; }
        public DateTimeOffset? ServerEndPeriod { get; set; }

        public virtual User User { get; set; }
        public virtual ICollection<AnalysisLog> AnalysisLogs { get; set; }
    }
}
