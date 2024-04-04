using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Data.Core
{
    /// <summary>
    /// Class helper of Stat unit types
    /// </summary>
    public static class StatisticalUnitsTypeHelper
    {
        private static readonly Dictionary<Type, StatUnitTypes> TypeToEnum = new Dictionary<Type, StatUnitTypes>
        {
            [typeof(LocalUnit)] = StatUnitTypes.LocalUnit,
            [typeof(LegalUnit)] = StatUnitTypes.LegalUnit,
            [typeof(EnterpriseUnit)] = StatUnitTypes.EnterpriseUnit,
            [typeof(EnterpriseGroup)] = StatUnitTypes.EnterpriseGroup
        };

        private static readonly Dictionary<StatUnitTypes, Type> EnumToType =
            TypeToEnum.ToDictionary(v => v.Value, v => v.Key);

        /// <summary>
        /// Method for obtaining types by stat. unit
        /// </summary>
        /// <param name="unitType">Type of stat. units</param>
        /// <returns></returns>
        public static StatUnitTypes GetStatUnitMappingType(Type unitType) => TypeToEnum[unitType];

        /// <summary>
        /// Method for getting type by enumeration
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <returns></returns>
        public static Type GetStatUnitMappingType(StatUnitTypes type) => EnumToType[type];
    }
}
