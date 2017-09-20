using System;

namespace nscreg.Utilities
{
    public static class DataAccessAttributesHelper
    {
        public static string GetName<T>(string propName)
        {
            return GetName(typeof(T), propName);
        }

        public static string GetName(Type type, string propName)
        {
            return $"{type.Name}.{propName}";
        }
    }
}
