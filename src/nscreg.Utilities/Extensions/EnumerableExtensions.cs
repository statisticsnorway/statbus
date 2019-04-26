using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Utilities.Extensions
{
    /// <summary>
    /// Класс перечисления расширений
    /// </summary>
    public static class EnumerableExtensions
    {
        /// <summary>
        /// Асинхронный метод выборки
        /// </summary>
        /// <param name="source">Ресурс</param>
        /// <param name="task">Задача</param>
        /// <returns></returns>
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
        /// Метод обработки коллекции
        /// </summary>
        /// <param name="source">Ресурс</param>
        /// <param name="action">Действие</param>
        public static void ForEach<T>(this IEnumerable<T> source, Action<T> action)
        {
            foreach (var item in source)
                action(item);
        }

        /// <summary>
        /// Асинхронный метод обработки коллекции
        /// </summary>
        /// <param name="source">Ресурс</param>
        /// <param name="action">Действие</param>
        /// <returns></returns>
        public static async Task ForEachAsync<T>(this IEnumerable<T> source, Func<T, Task> action)
        {
            foreach (var item in source)
                await action(item);
        }

        /// <summary>
        /// Метод добавления диапазона значений
        /// </summary>
        /// <param name="collection">Коллекция</param>
        /// <param name="values">Значения</param>
        public static void AddRange<T>(this ICollection<T> collection, IEnumerable<T> values)
        {
            values.ForEach(collection.Add);
        }

        /// <summary>
        /// Метод сравнения двух объектов
        /// </summary>
        /// <param name="first">Первый</param>
        /// <param name="second">Второй</param>
        /// <param name="keySelector">Ключ выборки</param>
        /// <returns></returns>
        public static bool CompareWith<T, TKey>(this IEnumerable<T> first, IEnumerable<T> second, Func<T, TKey> keySelector)
        {
            HashSet<TKey> firstSet = new HashSet<TKey>(first.Select(keySelector)),
                secondSet = new HashSet<TKey>(second.Select(keySelector));
            return secondSet.All(key => firstSet.Remove(key)) && firstSet.Count == 0;
        }
    }
}
