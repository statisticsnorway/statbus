using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    public class SectorCode : CodeLookupBase
    {
        public int? ParentId { get; set; }
        public virtual SectorCode Parent { get; set; }
        public virtual ICollection<SectorCode> SectorCodes { get; set; } = new HashSet<SectorCode>();
    }
}
