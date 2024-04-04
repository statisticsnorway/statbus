using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Utilities.Extensions
{
    /// <summary>
    /// Extension Enumeration Class
    /// </summary>
    public static class EnumerableExtensions
    {
        /// <summary>
        /// Asynchronous sampling method
        /// </summary>
        /// <param name = "source"> Resource </param>
        /// <param name = "task"> Task </param>
        /// <returns> </returns>
        public static async Task<IEnumerable<TResult>> SelectAsync<TSource, TResult>(
            this IEnumerable<TSource> source,
            Func<TSource, Task<TResult>> task)
        {
            var result = new List<TResult>();
            foreach (var item in source)
            {
                result.Add(await task(item));
            }
            return result;
        }

        /// <summary>
        /// Collection processing method
        /// </summary>
        /// <param name = "source"> Resource </param>
        /// <param name = "action"> Action </param>
        public static void ForEach<T>(this IEnumerable<T> source, Action<T> action)
        {
            foreach (var item in source)
                action(item);
        }

        /// <summary>
        /// Asynchronous collection processing method
        /// </summary>
        /// <param name = "source"> Resource </param>
        /// <param name = "action"> Action </param>
        /// <returns> </returns>
        public static async Task ForEachAsync<T>(this IEnumerable<T> source, Func<T, Task> action)
        {
            foreach (var item in source)
                await action(item);
        }

        /// <summary>
        /// Method for adding a range of values
        /// </summary>
        /// <param name = "collection"> Collection </param>
        /// <param name = "values"> Values </param>
        public static void AddRange<T>(this ICollection<T> collection, IEnumerable<T> values)
        {
            values.ForEach(collection.Add);
        }

        /// <summary>
        /// Method for comparing two objects
        /// </summary>
        /// <param name = "first"> First </param>
        /// <param name = "second"> Second </param>
        /// <param name = "keySelector"> Fetch key </param>
        /// <returns> </returns>
        public static bool CompareWith<T, TKey>(this IEnumerable<T> first, IEnumerable<T> second, Func<T, TKey> keySelector)
        {
            HashSet<TKey> firstSet = new HashSet<TKey>(first.Select(keySelector)),
                secondSet = new HashSet<TKey>(second.Select(keySelector));
            return secondSet.All(key => firstSet.Remove(key)) && firstSet.Count == 0;
        }
    }
}
