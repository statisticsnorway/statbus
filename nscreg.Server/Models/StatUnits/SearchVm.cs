using System.Collections.Generic;
// ReSharper disable UnusedAutoPropertyAccessor.Global
// ReSharper disable MemberCanBePrivate.Global

namespace nscreg.Server.Models.StatUnits
{
    public class SearchVm
    {
        private SearchVm(IEnumerable<object> items, int totalCount, int totalPages)
        {
            Result = items;
            TotalCount = totalCount;
            TotalPages = totalPages;
        }

        public static SearchVm Create(
            IEnumerable<object> items,
            int totalCount,
            int totalPages) => new SearchVm(items, totalCount, totalPages);

        public IEnumerable<object> Result { get; }
        public int TotalCount { get; }
        public int TotalPages { get; }
    }
}
