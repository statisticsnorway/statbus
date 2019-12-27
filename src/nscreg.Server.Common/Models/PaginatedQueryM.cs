using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models
{
    /// <summary>
    /// Pagination Request Model
    /// </summary>
    public class PaginatedQueryM
    {
        [Range(1, int.MaxValue)]
        public int Page { get; set; } = 1;

        [Range(5, 100)]
        public int PageSize { get; set; } = 10;

        public string SortBy { get; set; }

        public bool SortAscending { get; set; }
    }
}
