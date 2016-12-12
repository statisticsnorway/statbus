using System.Collections.Generic;

namespace nscreg.Server.Models.StatUnits
{
    public class SearchVm
    {
        public static SearchVm Create(IEnumerable<string> items, int totalCount, int totalPages) =>
            new SearchVm
            {
                Result = items,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<string> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
    }
}
