using System;
using System.Reflection;

namespace nscreg.Utilities.Extensions
{
    /// <summary>
    /// Type extension class
    /// </summary>
    public static class TypeExtensions
    {
        /// <summary>
        /// Method for checking objects on Nullable
        /// </summary>
        /// <typeparam name = "T"> </typeparam>
        /// <param name = "obj"> </param>
        /// <returns> </returns>
        public static bool IsNullable<T>(this T obj)
        {
            if (obj == null) return true;
            var type = typeof(T);
            return !type.GetTypeInfo().IsValueType || Nullable.GetUnderlyingType(type) != null;
        }
    }
}
