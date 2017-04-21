using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Server.Models.DataAccess;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Services
{
    public class DataAcessAttributesProvider<T> where T : IStatisticalUnit
    {
        private static List<DataAccessAttributeM> ToDataAccessAttributeM(IEnumerable<PropertyInfo> properties)
        {
            return properties.Select(v =>
            {
                var displayAttribute = v.GetCustomAttribute<DisplayAttribute>();
                return Tuple.Create(
                    displayAttribute?.GetOrder() ?? int.MaxValue,
                    new DataAccessAttributeM()
                    {
                        Name = DataAccessAttributesHelper.GetName(typeof(T), v.Name),
                        GroupName = displayAttribute?.GroupName,
                        LocalizeKey = v.Name,
                    });
            }).OrderBy(v => v.Item1).Select(v => v.Item2).ToList();
        }

        public static readonly List<DataAccessAttributeM> Attributes =
            ToDataAccessAttributeM(typeof(T).GetProperties().Where(v =>
                v.GetCustomAttribute<NotMappedForAttribute>() == null &&
                v.GetCustomAttribute<DataAccessCommonAttribute>() == null
            ).ToList());

        public static readonly List<DataAccessAttributeM> CommonAttributes =
            ToDataAccessAttributeM(typeof(T).GetProperties().Where(v =>
                v.GetCustomAttribute<DataAccessCommonAttribute>() != null
            ).ToList());
    }

    public static class DataAcessAttributesProvider
    {
        public static readonly IReadOnlyCollection<DataAccessAttributeM> Attributes =
            DataAcessAttributesProvider<LegalUnit>.Attributes
                .Concat(DataAcessAttributesProvider<LocalUnit>.Attributes)
                .Concat(DataAcessAttributesProvider<EnterpriseGroup>.Attributes)
                .Concat(DataAcessAttributesProvider<EnterpriseUnit>.Attributes)
                .ToList();

        public static readonly IReadOnlyCollection<DataAccessAttributeM> CommonAttributes =
            DataAcessAttributesProvider<LegalUnit>.CommonAttributes
                .Concat(DataAcessAttributesProvider<LocalUnit>.CommonAttributes)
                .Concat(DataAcessAttributesProvider<EnterpriseGroup>.CommonAttributes)
                .Concat(DataAcessAttributesProvider<EnterpriseUnit>.CommonAttributes)
                .ToList();

        private static readonly Dictionary<string, DataAccessAttributeM> AttributeNames =
            Attributes.ToDictionary(v => v.Name);

        private static readonly Dictionary<string, DataAccessAttributeM> AllAttributeNames =
            Attributes.Concat(CommonAttributes).ToDictionary(v => v.Name);

        public static DataAccessAttributeM Find(string name, bool withCommon = false)
        {
            DataAccessAttributeM attr;
            var data = withCommon ? AllAttributeNames : AttributeNames;
            return data.TryGetValue(name, out attr) ? attr : null;
        }

    }

}
