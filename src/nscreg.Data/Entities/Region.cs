using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность регион
    /// </summary>
    public class Region : CodeLookupBase
    {
        public string AdminstrativeCenter { get; set; }
        public int? ParentId { get; set; }
        public virtual ICollection<UserRegion> UserRegions { get; set; }
    }
}
