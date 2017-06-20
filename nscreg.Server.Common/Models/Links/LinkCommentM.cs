using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.Links
{
    public class LinkCommentM : LinkSubmitM
    {
        [Required]
        public string Comment { get; set; }
    }
}
