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
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Models.StatUnits
{
    public static class StatUnitViewModelCreator
    {
        public static StatUnitViewModel Create(
            IStatisticalUnit domainEntity,
            DataAccessPermissions dataAccess,
            IReadOnlyDictionary<string, bool> mandatoryFields,
            ActionsEnum ignoredActions )
        {
            var authorizedProperties = GetAuthorizedProperties(domainEntity.GetType()).ToList();
            var properties = authorizedProperties.Select(x =>
                {
                    var hasMandatory = mandatoryFields.TryGetValue(x.PropInfo.Name, out var mandatory);
                    var property = PropertyMetadataFactory.Create(
                        x.PropInfo,
                        domainEntity,
                        x.Writable,
                        hasMandatory ? mandatory : null
                    );
                    return property;
                }
                ).ToList();
            return new StatUnitViewModel
            {
                StatUnitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(domainEntity.GetType()),
                Properties = properties,
                Permissions = dataAccess.Permissions.Where(x=>properties.Any(d=>x.PropertyName.EndsWith($".{d.LocalizeKey}"))).ToList() //TODO: Filter By Type (Optimization)
            };

            IEnumerable<(PropertyInfo PropInfo, bool Writable)> GetAuthorizedProperties(Type type)
                => type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                    .Where(x =>
                        dataAccess.HasWriteOrReadPermission(DataAccessAttributesHelper.GetName(type, x.Name))
                        && x.CanRead
                        && x.CanWrite
                        && (x.GetCustomAttribute<NotMappedForAttribute>(true) == null
                        || !x.GetCustomAttribute<NotMappedForAttribute>(true).Actions.HasFlag(ignoredActions))
                        )
                    .OrderBy(x => ((DisplayAttribute)x.GetCustomAttribute(typeof(DisplayAttribute)))?.GetOrder()?? int.MaxValue)
                    .Select(x => (x, dataAccess.HasWritePermission(DataAccessAttributesHelper.GetName(type, x.Name))));
        }
    }
}
