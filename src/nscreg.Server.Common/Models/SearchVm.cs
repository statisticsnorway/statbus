using System.Collections.Generic;

namespace nscreg.Server.Common.Models
{
    /// <summary>
    /// Вью модель поиска
    /// </summary>
    public class SearchVm<T> where T : class
    {
        private SearchVm(IEnumerable<T> items, long totalCount)
        {
            Result = items;
            TotalCount = totalCount;
        }

        /// <summary>
        /// Метод создания вью модели поиска
        /// </summary>
        /// <param name="items">Еденицы</param>
        /// <param name="totalCount">Общее количество</param>
        /// <returns></returns>
        public static SearchVm<T> Create(IEnumerable<T> items, long totalCount) => new SearchVm<T>(items, totalCount);

        public IEnumerable<T> Result { get; }
        public long TotalCount { get; }
    }
}
