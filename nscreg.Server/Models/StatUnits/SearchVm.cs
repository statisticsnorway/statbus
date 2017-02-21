using System.Collections.Generic;
// ReSharper disable UnusedAutoPropertyAccessor.Global
// ReSharper disable MemberCanBePrivate.Global

namespace nscreg.Server.Models.StatUnits
{
    public class SearchVm
    {
        public static SearchVm Create(IEnumerable<object> items, int totalCount, int totalPages) =>
            new SearchVm
            {
                Result = items,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<object> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
    }
}
