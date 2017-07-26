using System;
using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    public class AnalysisLog
    {
        public int Id { get; set; }
        public string UserId { get; set; }
        public DateTime? ServerStartPeriod { get; set; }
        public DateTime? ServerEndPeriod { get; set; }
        public string Comment { get; set; }
        public DateTime UserStartPeriod { get; set; }
        public DateTime UserEndPeriod { get; set; }
        public virtual User User { get; set; }
        public virtual ICollection<AnalysisError> AnalysisErrors { get; set; }
    }
}
