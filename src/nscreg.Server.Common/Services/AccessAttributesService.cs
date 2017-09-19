using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Services
{
    public static class AccessAttributesService
    {
        public static IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
            => ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions)))
                .Select(x => new KeyValuePair<int, string>((int) x, x.ToString()));

        public static DataAccessModel GetAllDataAccessAttributes() => DataAccessModel.FromString(null);
    }
}
