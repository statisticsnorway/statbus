using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkSubmitM
    {
        [Required]
        public UnitSubmitM Source1 { get; set; }
        [Required]
        public UnitSubmitM Source2 { get; set; }
    }
}
