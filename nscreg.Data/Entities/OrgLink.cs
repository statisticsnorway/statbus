using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Data.Entities
{
    public class OrgLink : LookupBase
    {
        public int? OrgLinkId { get; set; }
        public virtual OrgLink Parent { get; set; }
        public virtual ICollection<OrgLink> OrgLinks { get; set; } = new HashSet<OrgLink>();
    }
}
