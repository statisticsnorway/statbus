using System.Collections;
using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    public class SectorCode : LookupBase
    {
        public int? ParentId { get; set; }
        public string Code { get; set; }
        public virtual SectorCode Parent { get; set; }
        public virtual ICollection<SectorCode> SectorCodes { get; set; } = new HashSet<SectorCode>();
    }
}
