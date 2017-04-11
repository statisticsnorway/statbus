using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkCreateM : LinkM
    {
        [Required]
        public string Comment { get; set; }

        public bool Overwrite { get; set; }
    }
}
