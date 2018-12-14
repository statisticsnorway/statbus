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
        public virtual Region Parent { get; set; }
        public virtual ICollection<UserRegion> UserRegions { get; set; }
        public string FullPath { get; set; }
        public string FullPathLanguage1 { get; set; }
        public string FullPathLanguage2 { get; set; }
        public int? RegionLevel { get; set; }
    }
}
