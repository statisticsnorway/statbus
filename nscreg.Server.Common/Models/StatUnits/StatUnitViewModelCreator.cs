using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Utilities.Attributes;
using nscreg.ModelGeneration;
using nscreg.Utilities;

namespace nscreg.Server.Common.Models.StatUnits
{
    public static class StatUnitViewModelCreator
    {
        public static StatUnitViewModel Create(IStatisticalUnit domainEntity, ISet<string> propNames)
            => new StatUnitViewModel
            {
                StatUnitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(domainEntity.GetType()),
                Properties = CreateProperties(domainEntity, propNames).ToArray(),
                DataAccess = propNames, //TODO: Filter By Type (Optimization)
            };

        private static IEnumerable<PropertyMetadataBase> CreateProperties(
            IStatisticalUnit domainEntity,
            ISet<string> propNames)
            =>
                GetFilteredProperties(domainEntity.GetType(), propNames)
                    .Select(x => PropertyMetadataFactory.Create(x, domainEntity));

        private static IEnumerable<PropertyInfo> GetFilteredProperties(Type type, ISet<string> propNames)
            => type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(x =>
                    propNames.Contains(DataAccessAttributesHelper.GetName(type, x.Name))
                    && x.CanRead && x.CanWrite && x.GetCustomAttribute<NotMappedForAttribute>(true) == null
                )
                .OrderBy(x =>
                {
                    var order = (DisplayAttribute) x.GetCustomAttribute(typeof(DisplayAttribute));
                    return order?.GetOrder() ?? int.MaxValue;
                });
    }
}
