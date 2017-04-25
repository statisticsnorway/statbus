using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkCommentM : LinkSubmitM
    {
        [Required]
        public string Comment { get; set; }
    }
}
