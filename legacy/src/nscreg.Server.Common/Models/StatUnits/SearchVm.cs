using System.Collections.Generic;
using System.Linq;

// ReSharper disable UnusedAutoPropertyAccessor.Global
// ReSharper disable MemberCanBePrivate.Global

namespace nscreg.Server.Common.Models.StatUnits
{
    public class SearchVm
    {
        private SearchVm(IEnumerable<object> items, long totalCount)
        {
            Result = items;
            TotalCount = totalCount;
        }

        public static SearchVm Create(IEnumerable<object> items, long totalCount) => new SearchVm(items, totalCount);

        public IEnumerable<object> Result { get; }
        public long TotalCount { get; }
    }
}
