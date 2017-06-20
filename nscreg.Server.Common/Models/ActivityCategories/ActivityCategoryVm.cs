using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.ActivityCategories
{
    public class ActivityCategoryVm : CodeLookupVm
    {
        public new string Id { get; set; }
        public string Section { get; set; }
    }
}
