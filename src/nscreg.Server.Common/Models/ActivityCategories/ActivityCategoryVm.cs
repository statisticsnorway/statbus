using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.ActivityCategories
{
    /// <summary>
    /// Вью модель видов деятельности
    /// </summary>
    public class ActivityCategoryVm : CodeLookupVm
    {
        public string Section { get; set; }
        public int? ParentId { get; set; }
    }
}
