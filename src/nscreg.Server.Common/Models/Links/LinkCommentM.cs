using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Links
{
    /// <summary>
    /// Commenting Model
    /// </summary>
    public class LinkCommentM : LinkSubmitM
    {
        [Required]
        public string Comment { get; set; }
    }
}
