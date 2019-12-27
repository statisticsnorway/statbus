using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;

// both classes use getters as functions which involves some calculations on every execution
// it is because of unknown behavior (bug?) of evaluate-once properties with one-time initialization
// their value is changing between requests, e.g. first request gets attribute names as [unit type].[attrib name] (i.e. LocalUnit.StatId)
// while further responses will return same attribute names without type namespace, e.g. [attrib name] (i.e. StatId)
namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Data source queue service
    /// </summary>
    public static class DataAccessAttributesProvider<T> where T : IStatisticalUnit
    {
        /// <summary>
        /// Conversion Method
        /// </summary>
        public static List<DataAccessAttributeM> CommonAttributes => ToDataAccessAttributeM(
            typeof(T).GetProperties()
                .Where(v => v.GetCustomAttribute<DataAccessCommonAttribute>() != null)
                .ToList());

        public static List<DataAccessAttributeM> Attributes => ToDataAccessAttributeM(
            typeof(T).GetProperties()
                .Where(v =>
                    v.GetCustomAttribute<NotMappedForAttribute>() == null &&
                    v.GetCustomAttribute<DataAccessCommonAttribute>() == null)
                .ToList());

        private static List<DataAccessAttributeM> ToDataAccessAttributeM(IEnumerable<PropertyInfo> properties)
            => properties.Select(v =>
                {
                    var displayAttribute = v.GetCustomAttribute<DisplayAttribute>();
                    return Tuple.Create(
                        displayAttribute?.GetOrder() ?? int.MaxValue,
                        new DataAccessAttributeM
                        {
                            Name = DataAccessAttributesHelper.GetName(typeof(T), v.Name),
                            GroupName = displayAttribute?.GroupName,
                            LocalizeKey = v.Name,
                        });
                })
                .OrderBy(v => v.Item1)
                .Select(v => v.Item2)
                .ToList();
    }

    public static class DataAccessAttributesProvider
    {
        public static IReadOnlyCollection<DataAccessAttributeM> Attributes =>
            DataAccessAttributesProvider<LegalUnit>.Attributes
                .Concat(DataAccessAttributesProvider<LocalUnit>.Attributes)
                .Concat(DataAccessAttributesProvider<EnterpriseGroup>.Attributes)
                .Concat(DataAccessAttributesProvider<EnterpriseUnit>.Attributes)
                .ToList();

        public static IReadOnlyCollection<DataAccessAttributeM> CommonAttributes =>
            DataAccessAttributesProvider<LegalUnit>.CommonAttributes
                .Concat(DataAccessAttributesProvider<LocalUnit>.CommonAttributes)
                .Concat(DataAccessAttributesProvider<EnterpriseGroup>.CommonAttributes)
                .Concat(DataAccessAttributesProvider<EnterpriseUnit>.CommonAttributes)
                .ToList();

        public static DataAccessAttributeM Find(string name)
            => AttributeNames.TryGetValue(name, out DataAccessAttributeM attr)
                ? attr
                : null;

        private static readonly Dictionary<string, DataAccessAttributeM> AttributeNames =
            Attributes.ToDictionary(v => v.Name);
    }
}
