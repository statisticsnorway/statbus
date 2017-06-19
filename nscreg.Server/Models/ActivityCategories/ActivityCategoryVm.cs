using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.ActivityCategories
{
    public class ActivityCategoryVm : CodeLookupVm
    {
        public new string Id { get; set; }
        public string Section { get; set; }
    }
}
