using System;
using System.Reflection;

namespace nscreg.Utilities.Extensions
{
    public static class TypeExtensions
    {
        public static bool IsNullable<T>(this T obj)
        {
            if (obj == null) return true;
            var type = typeof(T);
            return !type.GetTypeInfo().IsValueType || Nullable.GetUnderlyingType(type) != null;
        }
    }
}
