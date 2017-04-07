using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Reflection;
using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Data.Constants;
using nscreg.Server.Models.DataAccess;
using nscreg.Utilities;

namespace nscreg.Server.Models.StatUnits
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class SearchItemVm
    {
        public static object Create<T>(T statUnit, StatUnitTypes type, ISet<string> propNames) where T : class
        {
            var dataAccess = DataAccessModel.FromString(propNames.Join(","));
            var propNamesForSearhResults =
                new HashSet<string>(propNames.Concat(
                    typeof(T).GetProperties()
                        .Where(x => dataAccess.IsAllowedInAllTypes(x.Name))
                        .Select(x => $"{typeof(T).Name}.{x.Name}")));

            return DataAccessResolver.Execute(statUnit, propNamesForSearhResults, jo => { jo.Add("type", (int)type); });
        }
    }
}