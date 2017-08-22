using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

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
        public int? LastAnalyzedUnitId { get; set; }
        public StatUnitTypes? LastAnalyzedUnitType { get; set; }
        public string SummaryMessages { get; set; }

        public virtual User User { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<AnalysisError> AnalysisErrors { get; set; }
    }
}
