using System;
using System.Reflection;

namespace nscreg.Utilities.Extensions
{
    /// <summary>
    /// Класс расширения типов
    /// </summary>
    public static class TypeExtensions
    {
        /// <summary>
        /// Метод проверки объектов на Nullable
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="obj"></param>
        /// <returns></returns>
        public static bool IsNullable<T>(this T obj)
        {
            if (obj == null) return true;
            var type = typeof(T);
            return !type.GetTypeInfo().IsValueType || Nullable.GetUnderlyingType(type) != null;
        }
    }
}
