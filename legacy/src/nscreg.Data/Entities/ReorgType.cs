using System.Collections.Generic;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Entities
{
    /// <summary>
    /// Reorg Type classificator
    /// </summary>
    public class ReorgType: CodeLookupBase
    {
        public virtual List<EnterpriseGroupHistory> EnterpriseGroupHistories { get; set; }
    }
}
