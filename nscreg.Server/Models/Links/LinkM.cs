using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkM
    {
        [Required]
        public UnitLookupVm Source1 { get; set; }
        [Required]
        public UnitLookupVm Source2 { get; set; }
    }
}
