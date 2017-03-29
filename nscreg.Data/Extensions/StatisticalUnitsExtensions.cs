using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Data.Extensions
{
    public abstract class StatisticalUnitsExtensions
    {
        private static readonly Dictionary<Type, StatUnitTypes> MapType = new Dictionary<Type, StatUnitTypes>
        {
            [typeof(LocalUnit)] = StatUnitTypes.LocalUnit,
            [typeof(LegalUnit)] = StatUnitTypes.LegalUnit,
            [typeof(EnterpriseUnit)] = StatUnitTypes.EnterpriseUnit,
            [typeof(EnterpriseGroup)] = StatUnitTypes.EnterpriseGroup
        };

        public static StatUnitTypes GetStatUnitMappingType(Type unitType)
        {
            StatUnitTypes type;
            if (!MapType.TryGetValue(unitType, out type))
            {
                throw new ArgumentException();
            }
            return type;
        }
    }
}
