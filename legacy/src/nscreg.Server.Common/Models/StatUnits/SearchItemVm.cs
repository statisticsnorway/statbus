using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Utilities;

namespace nscreg.Server.Common.Models.StatUnits
{
    public static class SearchItemVm
    {
        public static object Create<T>(T statUnit, StatUnitTypes type, ISet<string> propNames, bool? isReadonly = null) where T : class
        {
            var unitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(type);
            if (unitType != typeof(T))
            {
                var currentType = statUnit.GetType();
                propNames = new HashSet<string>(
                    currentType.GetProperties()
                        .Where(v => propNames.Contains(DataAccessAttributesHelper.GetName(unitType, v.Name)))
                        .Select(v => DataAccessAttributesHelper.GetName(currentType, v.Name))
                        .ToList()
                );
            }
            return DataAccessResolver.Execute(statUnit, propNames, jo => { jo.Add("type", (int)type); jo.Add("readonly", isReadonly); });
        }
    }
}
