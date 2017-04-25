using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models
{
    public class PaginationModel
    {

        [Range(1, int.MaxValue)]
        public int Page { get; set; } = 1;

        [Range(5, 100)]
        public int PageSize { get; set; } = 10;
    }
}
