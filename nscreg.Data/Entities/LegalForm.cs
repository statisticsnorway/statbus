using System.Collections;
using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    public class LegalForm : LookupBase
    {
        public int? ParentId { get; set; }
        public virtual LegalForm Parent { get; set; }
        public virtual ICollection<LegalForm> LegalForms { get; set; } = new HashSet<LegalForm>();
    }
}
