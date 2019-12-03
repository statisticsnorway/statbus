using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.Links
{
    /// <summary>
    /// Link Sending Model
    /// </summary>
    public class LinkSubmitM
    {
        [Required]
        public UnitSubmitM Source1 { get; set; }
        [Required]
        public UnitSubmitM Source2 { get; set; }
    }
}
