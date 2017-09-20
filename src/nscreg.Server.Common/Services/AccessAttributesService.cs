using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Класс сервис атрибутов доступа
    /// </summary>
    public static class AccessAttributesService
    {
        /// <summary>
        /// Метод получения всех системных функций
        /// </summary>
        /// <returns></returns>
        public static IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
            => ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions)))
                .Select(x => new KeyValuePair<int, string>((int) x, x.ToString()));

        /// <summary>
        /// Метод получения всех атрибутов доступа к данным
        /// </summary>
        /// <returns></returns>
        public static DataAccessModel GetAllDataAccessAttributes() => DataAccessModel.FromString(null);
    }
}
