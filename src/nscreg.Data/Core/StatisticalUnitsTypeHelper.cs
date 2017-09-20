using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Data.Core
{
    /// <summary>
    /// Класс хелпер типов стат. единицы
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
        /// Метод получения типов по стат. единице
        /// </summary>
        /// <param name="unitType">Тип стат. единицы</param>
        /// <returns></returns>
        public static StatUnitTypes GetStatUnitMappingType(Type unitType) => TypeToEnum[unitType];

        /// <summary>
        /// Метод получения типов  по перечислению
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <returns></returns>
        public static Type GetStatUnitMappingType(StatUnitTypes type) => EnumToType[type];
    }
}
