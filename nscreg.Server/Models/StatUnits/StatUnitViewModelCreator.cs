using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Extensions;
using nscreg.Utilities.Attributes;
using nscreg.ModelGeneration;

namespace nscreg.Server.Models.StatUnits
{
    public class StatUnitViewModelCreator
    {
        

        public ViewModelBase Create(IStatisticalUnit domainEntity, ISet<string> propNames)
        {
            return new StatUnitViewModel
            {
                StatUnitType = StatisticalUnitsExtensions.GetStatUnitMappingType(domainEntity.GetType()),
                Properties = CreateProperties(domainEntity, propNames).ToArray(),
                DataAccess = propNames, //TODO: Filter By Type (Optimization)
            };
        }

        private IEnumerable<PropertyMetadataBase> CreateProperties(IStatisticalUnit domainEntity,
            ISet<string> propNames)
        {
            var propsToAdd = GetFilteredProperties(domainEntity.GetType(), propNames);
            return propsToAdd.Select(x => PropertyMetadataFactory.Create(x, domainEntity));
        }

        private IEnumerable<PropertyInfo> GetFilteredProperties(Type type, ISet<string> propNames)
            => type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(
                    x =>
                        propNames.Contains($"{type.Name}.{x.Name}", StringComparer.OrdinalIgnoreCase)
                        && x.CanRead
                        && x.CanWrite
                        && !x.GetCustomAttributes(typeof(NotMappedForAttribute), true)
                            .Cast<NotMappedForAttribute>()
                            .Any())
                .OrderBy(x =>
                {
                    var order = (DisplayAttribute)x.GetCustomAttribute(typeof(DisplayAttribute));
                    return order?.Order ?? int.MaxValue;
                });
    }
}
