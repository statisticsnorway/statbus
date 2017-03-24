using System.Collections.Generic;
// ReSharper disable UnusedAutoPropertyAccessor.Global
// ReSharper disable MemberCanBePrivate.Global

namespace nscreg.Server.Models.StatUnits
{
    public class SearchVm
    {
        private SearchVm(IEnumerable<object> items, int totalCount)
        {
            Result = items;
            TotalCount = totalCount;
        }

        public static SearchVm Create(IEnumerable<object> items, int totalCount) => new SearchVm(items, totalCount);

        public IEnumerable<object> Result { get; }
        public int TotalCount { get; }
    }
}
