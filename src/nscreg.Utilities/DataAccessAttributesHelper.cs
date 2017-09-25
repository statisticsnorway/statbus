using System;

namespace nscreg.Utilities
{
    /// <summary>
    /// Класс хелпер атрибутов доступа к данным
    /// </summary>
    public static class DataAccessAttributesHelper
    {
        /// <summary>
        /// Метод получения имени атрибута доступа к данным
        /// </summary>
        /// <param name="propName">Имя свойства</param>
        /// <returns></returns>
        public static string GetName<T>(string propName)
        {
            return GetName(typeof(T), propName);
        }

        /// <summary>
        /// Метод получения имени атрибута доступа к данным
        /// </summary>
        /// <param name="type">Тип свойства</param>
        /// <param name="propName">Имя свойства</param>
        /// <returns></returns>
        public static string GetName(Type type, string propName)
        {
            return $"{type.Name}.{propName}";
        }
    }
}
