using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.Links
{
    /// <summary>
    /// Communication model
    /// </summary>
    public class LinkM
    {
        [Required]
        public UnitLookupVm Source1 { get; set; }
        [Required]
        public UnitLookupVm Source2 { get; set; }
    }
}
