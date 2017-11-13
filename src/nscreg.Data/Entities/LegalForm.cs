using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность правовая форма собственности
    /// </summary>
    public class LegalForm : CodeLookupBase
    {
        public int? ParentId { get; set; }
        public virtual LegalForm Parent { get; set; }
        public virtual ICollection<LegalForm> LegalForms { get; set; } = new HashSet<LegalForm>();
    }
}
