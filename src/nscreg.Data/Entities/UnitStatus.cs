using System.Collections.Generic;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Entities
{
    /// <summary>
    /// Stat Unit status classificator
    /// </summary>
    public class UnitStatus : CodeLookupBase
    {
        public virtual List<EnterpriseGroupHistory> EnterpriseGroupHistories { get; set; }
    }
}
