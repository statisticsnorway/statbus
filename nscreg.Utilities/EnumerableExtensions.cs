using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace nscreg.Utilities
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
    }
}
