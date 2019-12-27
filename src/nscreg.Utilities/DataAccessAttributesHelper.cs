using System;

namespace nscreg.Utilities
{
    /// <summary>
    /// Data Access Attributes Helper Class
    /// </summary>
    public static class DataAccessAttributesHelper
    {
        /// <summary>
        /// Method for obtaining the name of the data access attribute
        /// </summary>
        /// <param name = "propName"> Property name </param>
        /// <returns> </returns>
        public static string GetName<T>(string propName)
        {
            return GetName(typeof(T), propName);
        }

        /// <summary>
        /// Method for obtaining the name of the data access attribute
        /// </summary>
        /// <param name = "type"> Property type </param>
        /// <param name = "propName"> Property name </param>
        /// <returns> </returns>
        public static string GetName(Type type, string propName)
        {
            return $"{type.Name}.{propName}";
        }
    }
}
