using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Helpers;
using nscreg.ModelGeneration;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Models.StatUnits
{
    public class StatUnitViewModel : ViewModelBase
    {
        // ReSharper disable once MemberCanBePrivate.Global
        public StatUnitTypes StatUnitType { get; set; }

        // ReSharper disable once MemberCanBePrivate.Global
        public ICollection<string> DataAccess { get; set; }

        public static StatUnitViewModel Create(IStatisticalUnit domainEntity, ISet<string> propNames)
            => new StatUnitViewModel
            {
                StatUnitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(domainEntity.GetType()),
                Properties = CreateProperties(domainEntity, propNames).ToArray(),
                DataAccess = propNames, //TODO: Filter By Type (Optimization)
            };

        private static IEnumerable<PropertyMetadataBase> CreateProperties(
            IStatisticalUnit domainEntity,
            ICollection<string> propNames)
            => GetFilteredProperties(domainEntity.GetType(), propNames)
                .Select(x => PropertyMetadataFactory.Create(x, domainEntity));

        private static IEnumerable<PropertyInfo> GetFilteredProperties(Type type, ICollection<string> propNames)
            => type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(x =>
                    propNames.Contains(DataAccessAttributesHelper.GetName(type, x.Name))
                    && x.CanRead
                    && x.CanWrite
                    && x.GetCustomAttribute<NotMappedForAttribute>(true) == null)
                .OrderBy(x =>
                    ((DisplayAttribute) x.GetCustomAttribute(typeof(DisplayAttribute)))?.GetOrder()
                    ?? int.MaxValue);
    }
}
