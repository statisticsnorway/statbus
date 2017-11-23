using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.ModelGeneration;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Common.Models.StatUnits
{
    public static class StatUnitViewModelCreator
    {
        public static StatUnitViewModel Create(IStatisticalUnit domainEntity, DataAccessPermissions permissions)
        {
            return new StatUnitViewModel
            {
                StatUnitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(domainEntity.GetType()),
                Properties = CreateProperties(domainEntity, permissions).ToArray(),
                DataAccess = permissions //TODO: Filter By Type (Optimization)
            };
        }

        private static IEnumerable<PropertyMetadataBase> CreateProperties(
            IStatisticalUnit domainEntity,
            DataAccessPermissions permissions)
        {
            return GetFilteredProperties(domainEntity.GetType(), permissions)
                .Select(x => PropertyMetadataFactory.Create(x.Item1, domainEntity, x.Item2));
        }

        private static IEnumerable<Tuple<PropertyInfo, bool>> GetFilteredProperties(Type type,
            DataAccessPermissions permissions)
        {
            return type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(x =>
                    permissions.HasWriteOrReadPermission(DataAccessAttributesHelper.GetName(type, x.Name))
                    && x.CanRead
                    && x.CanWrite
                    && x.GetCustomAttribute<NotMappedForAttribute>(true) == null
                )
                .OrderBy(x =>
                {
                    var order = (DisplayAttribute) x.GetCustomAttribute(typeof(DisplayAttribute));
                    return order?.GetOrder() ?? int.MaxValue;
                })
                .Select(x =>
                    Tuple.Create(x, permissions.HasWritePermission(DataAccessAttributesHelper.GetName(type, x.Name))));
        }
    }
}
