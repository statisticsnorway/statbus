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

        [JsonIgnore]
        public virtual ICollection<ActivityCategoryRole> ActivityCategoryRoles { get; set; }
    }
}
