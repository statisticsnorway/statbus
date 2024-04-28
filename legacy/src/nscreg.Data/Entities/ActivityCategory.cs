using System.Collections.Generic;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity type of activity
    /// </summary>
    public class ActivityCategory : CodeLookupBase
    {
        public string Section { get; set; }
        public int? ParentId { get; set; }
        public int? DicParentId { get; set; }
        public int VersionId { get; set; }
        public int? ActivityCategoryLevel { get; set; }

        public virtual ActivityCategory Parent { get; set; }
        public virtual IEnumerable<ActivityCategory> Children { get; set; } = new HashSet<ActivityCategory>();

        [JsonIgnore]
        public virtual ICollection<ActivityCategoryUser> ActivityCategoryUsers { get; set; }
    }
}
