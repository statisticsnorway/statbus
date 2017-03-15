using System.ComponentModel.DataAnnotations;
using nscreg.Resources.Languages;

namespace nscreg.Server.Models.Regions
{
    public class RegionM
    {
        [Required(ErrorMessage = nameof(Resource.RegionNameIsRequiredError)), DataType(DataType.Text)]
        public string Name { get; set; }
    }
}