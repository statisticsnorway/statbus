using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Common.Services
{
    public class DataAccessAttributesProvider<T> where T : IStatisticalUnit
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

    public static class DataAccessAttributesProvider
    {
        public static readonly IReadOnlyCollection<DataAccessAttributeM> Attributes =
            DataAccessAttributesProvider<LegalUnit>.Attributes
                .Concat(DataAccessAttributesProvider<LocalUnit>.Attributes)
                .Concat(DataAccessAttributesProvider<EnterpriseGroup>.Attributes)
                .Concat(DataAccessAttributesProvider<EnterpriseUnit>.Attributes)
                .ToList();

        public static readonly IReadOnlyCollection<DataAccessAttributeM> CommonAttributes =
            DataAccessAttributesProvider<LegalUnit>.CommonAttributes
                .Concat(DataAccessAttributesProvider<LocalUnit>.CommonAttributes)
                .Concat(DataAccessAttributesProvider<EnterpriseGroup>.CommonAttributes)
                .Concat(DataAccessAttributesProvider<EnterpriseUnit>.CommonAttributes)
                .ToList();

        private static readonly Dictionary<string, DataAccessAttributeM> AttributeNames =
            Attributes.ToDictionary(v => v.Name);


        public static DataAccessAttributeM Find(string name)
        {
            DataAccessAttributeM attr;
            var data = AttributeNames;
            return data.TryGetValue(name, out attr) ? attr : null;
        }

    }

}
