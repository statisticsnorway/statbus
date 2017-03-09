using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.ModelGeneration.ModelCreators;
using nscreg.Server.Models.Dynamic.Property;
using nscreg.Server.Models.Infrastructure;
using nscreg.Server.Models.StatUnits;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.ModelGeneration.ViewModelCreators
{
    public class StatUnitViewModelCreator : IViewModelCreator<IStatisticalUnit>
    {
        private static readonly Dictionary<Type, StatUnitTypes> MapType = new Dictionary<Type, StatUnitTypes>
        {
            [typeof(LocalUnit)] = StatUnitTypes.LocalUnit,
            [typeof(LegalUnit)] = StatUnitTypes.LegalUnit,
            [typeof(EnterpriseUnit)] = StatUnitTypes.EnterpriseUnit,
            [typeof(EnterpriseGroup)] = StatUnitTypes.EnterpriseGroup
        };

        public ViewModelBase Create(IStatisticalUnit domainEntity, HashSet<string> propNames)
        {
            if (!MapType.ContainsKey(domainEntity.GetType()))
                throw new ArgumentException();
            return new StatUnitViewModel
            {
                StatUnitType = MapType[domainEntity.GetType()],
                Properties = CreateProperties(domainEntity, propNames).ToArray()
            };
        }

        private IEnumerable<PropertyMetadataBase> CreateProperties(IStatisticalUnit domainEntity,
            HashSet<string> propNames)
        {
            var propsToAdd = GetFilteredProperties(domainEntity.GetType(), propNames);
            return propsToAdd.Select(x => PropertyMetadataFactory.Create(x, domainEntity));
        }

        private IEnumerable<PropertyInfo> GetFilteredProperties(Type type, HashSet<string> propNames)
            => type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(
                    x =>
                        propNames.Contains(x.Name, StringComparer.OrdinalIgnoreCase)
                        && x.CanRead
                        && x.CanWrite
                        && !x.GetCustomAttributes(typeof(NotMappedForAttribute), true)
                            .Cast<NotMappedForAttribute>()
                            .Any())
                .OrderBy(x =>
                {
                    var order = (DisplayAttribute) x.GetCustomAttribute(typeof(DisplayAttribute));
                    return order?.Order ?? int.MaxValue;
                });
    }
}