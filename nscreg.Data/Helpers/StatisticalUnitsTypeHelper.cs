using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Data.Helpers
{
    public static class StatisticalUnitsTypeHelper
    {
        private static readonly Dictionary<Type, StatUnitTypes> TypeToEnum = new Dictionary<Type, StatUnitTypes>
        {
            [typeof(LocalUnit)] = StatUnitTypes.LocalUnit,
            [typeof(LegalUnit)] = StatUnitTypes.LegalUnit,
            [typeof(EnterpriseUnit)] = StatUnitTypes.EnterpriseUnit,
            [typeof(EnterpriseGroup)] = StatUnitTypes.EnterpriseGroup
        };

        private static readonly Dictionary<StatUnitTypes, Type> EnumToType = TypeToEnum.ToDictionary(v => v.Value, v => v.Key);

        public static StatUnitTypes GetStatUnitMappingType(Type unitType)
        {
            return TypeToEnum[unitType];
        }

        public static Type GetStatUnitMappingType(StatUnitTypes type)
        {
            return EnumToType[type];
        }
    }
}
