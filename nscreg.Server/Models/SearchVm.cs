using System.Collections.Generic;

namespace nscreg.Server.Models
{
    public class SearchVm<T> where T : class
    {
        private SearchVm(IEnumerable<T> items, int totalCount)
        {
            Result = items;
            TotalCount = totalCount;
        }

        public static SearchVm<T> Create(IEnumerable<T> items, int totalCount) => new SearchVm<T>(items, totalCount);

        public IEnumerable<T> Result { get; }
        public int TotalCount { get; }
    }
}
