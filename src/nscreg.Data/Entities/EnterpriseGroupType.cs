using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Entities
{
    /// <summary>
    /// Enterprise Group type Entity
    /// </summary>
    public class EnterpriseGroupType : CodeLookupBase
    {
        public List<EnterpriseGroup> EnterpriseGroups { get; set; }
        public virtual List<EnterpriseGroupHistory> EnterpriseGroupsHistories { get; set; }
    }
}
