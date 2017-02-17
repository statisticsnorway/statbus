using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.ModelGeneration;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.ModelGeneration;

namespace nscreg.Server.Models.StatUnits
{
    public static class StatUnitViewModelCreator
    {
        private static readonly Dictionary<Type, StatUnitTypes> MapType = new Dictionary<Type, StatUnitTypes>
        {
            [typeof(LocalUnit)] = StatUnitTypes.LocalUnit,
            [typeof(LegalUnit)] = StatUnitTypes.LegalUnit,
            [typeof(EnterpriseUnit)] = StatUnitTypes.EnterpriseUnit,
            [typeof(EnterpriseGroup)] = StatUnitTypes.EnterpriseGroup
        };

        public static StatUnitViewModel Create(IStatisticalUnit domainEntity, string[] propNames)
        {
            if (!MapType.ContainsKey(domainEntity.GetType()))
                throw new ArgumentException();
            return new StatUnitViewModel
            {
                StatUnitType = MapType[domainEntity.GetType()],
                Properties = CreateProperties(domainEntity, propNames).ToArray()
            };
        }

        private static IEnumerable<PropertyMetadataBase> CreateProperties(
            IStatisticalUnit domainEntity,
            string[] propNames)
            => GetFilteredProperties(domainEntity.GetType(), propNames)
                .Select(x => PropertyMetadataFactory.Create(x, domainEntity));

        private static IEnumerable<PropertyInfo> GetFilteredProperties(Type type, string[] propNames)
            => type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(
                    x =>
                        propNames.Contains(x.Name, StringComparer.OrdinalIgnoreCase)
                        && x.CanRead
                        && x.CanWrite
                        && !x.GetCustomAttributes(typeof(NotMappedForAttribute), true)
                            .Cast<NotMappedForAttribute>()
                            .Any());
    }
}
