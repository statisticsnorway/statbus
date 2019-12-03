using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Access attribute service class
    /// </summary>
    public static class AccessAttributesService
    {
        /// <summary>
        /// Method for obtaining all system functions
        /// </summary>
        /// <returns> </returns>
        public static IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
            => ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions)))
                .Select(x => new KeyValuePair<int, string>((int) x, x.ToString()));

        /// <summary>
        /// Method for obtaining all data access attributes
        /// </summary>
        /// <returns> </returns>
        public static DataAccessModel GetAllDataAccessAttributes() => DataAccessModel.FromString(null);
    }
}
