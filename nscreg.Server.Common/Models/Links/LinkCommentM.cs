using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Links
{
    public class LinkCommentM : LinkSubmitM
    {
        [Required]
        public string Comment { get; set; }
    }
}
