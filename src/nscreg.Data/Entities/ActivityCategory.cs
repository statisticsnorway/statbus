using System.Collections.Generic;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность вид деятельности
    /// </summary>
    public class ActivityCategory : CodeLookupBase
    {
        public string Section { get; set; }
        public int? ParentId { get; set; }
        public int? DicParentId { get; set; }
        public int VersionId { get; set; }

        [JsonIgnore]
        public virtual ICollection<ActivityCategoryUser> ActivityCategoryUsers { get; set; }
    }
}
