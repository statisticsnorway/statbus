using System;
using System.Reflection;

namespace nscreg.Utilities
{
    public static class TypeExtensions
    {
        public static bool IsNullable<T>(this T obj)
        {
            if (obj == null) return true;
            var type = typeof(T);
            if (!type.GetTypeInfo().IsValueType) return true;
            if (Nullable.GetUnderlyingType(type) != null) return true;
            return false;
        }
    }
}