using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Utilities.Extensions
{
    public static class EnumerableExtensions
    {
        public static void ForEach<T>(this IEnumerable<T> source, Action<T> action)
        {
            foreach (var item in source)
                action(item);
        }

        public static async Task ForEachAsync<T>(this IEnumerable<T> source, Func<T, Task> action)
        {
            foreach (var item in source)
                await action(item);
        }

        public static void AddRange<T>(this ICollection<T> collection, IEnumerable<T> values)
        {
            values.ForEach(collection.Add);
        }

        public static bool CompareWith<T, TKey>(this IEnumerable<T> first, IEnumerable<T> second, Func<T, TKey> keySelector)
        {
            HashSet<TKey> firstSet = new HashSet<TKey>(first.Select(keySelector)),
                secondSet = new HashSet<TKey>(second.Select(keySelector));
            foreach (var key in secondSet)
            {
                if (!firstSet.Remove(key))
                {
                    return false;
                }
            }
            return firstSet.Count == 0;
        }
    }
}
