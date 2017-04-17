using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkCommentM : LinkM
    {
        [Required]
        public string Comment { get; set; }
    }
}
