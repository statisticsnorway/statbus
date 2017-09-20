using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность регион
    /// </summary>
    public class Region : LookupBase
    {
        public string Code { get; set; }

        public string AdminstrativeCenter { get; set; }
        public virtual ICollection<UserRegion> UserRegions { get; set; }
    }
}
