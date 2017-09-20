using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Links
{
    /// <summary>
    /// Модель комментирования связи
    /// </summary>
    public class LinkCommentM : LinkSubmitM
    {
        [Required]
        public string Comment { get; set; }
    }
}
