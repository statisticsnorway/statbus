using System.Collections.Generic;
// ReSharper disable UnusedAutoPropertyAccessor.Global
// ReSharper disable MemberCanBePrivate.Global

namespace nscreg.Server.Models.DataSources
{
    public class SearchVm
    {
        private SearchVm(IEnumerable<SearchItemVm> items, int totalCount)
        {
            Result = items;
            TotalCount = totalCount;
        }

        public static SearchVm Create(IEnumerable<SearchItemVm> items, int totalCount) => new SearchVm(items, totalCount);

        public IEnumerable<SearchItemVm> Result { get; }
        public int TotalCount { get; }
    }
}
