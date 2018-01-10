using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Utilities.Extensions;
using static nscreg.Business.DataSources.PropertyParser;
using static nscreg.Utilities.JsonPathHelper;

namespace nscreg.Business.DataSources
{
    public static class StatUnitKeyValueParser
    {
        public static string GetStatIdSourceKey(IEnumerable<(string source, string target)> mapping)
            => mapping.SingleOrDefault(vm => vm.target == nameof(StatisticalUnit.StatId)).source;

        public static void ParseAndMutateStatUnit(
            IReadOnlyDictionary<string, string> mappings,
            IReadOnlyDictionary<string, string> nextProps,
            StatisticalUnit unit)
        {
            var aggregated = nextProps.Aggregate(new Dictionary<string, string>(), AggregateAllFlattenPropsToJson);
            foreach (var kv in aggregated)
            {
                if (!mappings.TryGetValue(kv.Key, out var tmpKey)) continue;
                try
                {
                    UpdateObject(tmpKey, kv.Value);
                }
                catch (Exception ex)
                {
                    ex.Data.Add("source property", kv.Key);
                    ex.Data.Add("target property", tmpKey);
                    ex.Data.Add("value", kv.Value);
                    ex.Data.Add("unit", unit);
                    throw;
                }
            }

            Dictionary<string, string> AggregateAllFlattenPropsToJson(
                Dictionary<string, string> accumulation,
                KeyValuePair<string, string> cur)
            {
                if (!cur.Key.Contains('.'))
                {
                    accumulation.Add(cur.Key, cur.Value);
                    return accumulation;
                }
                var topKey = cur.Key.Split('.')[0];
                if (!accumulation.TryGetValue(topKey, out var previous)) previous = "{}";
                accumulation[topKey] = ReplacePath(previous, cur.Key, cur.Value);
                return accumulation;
            }

            void UpdateObject(string propPath, string value)
            {
                var propHead = PathHead(propPath);
                var propTail = PathTail(propPath);
                var unitType = unit.GetType();
                var propInfo = unitType.GetProperty(propHead);
                if (propInfo == null)
                {
                    throw new Exception(
                        $"Property `{propHead}` not found in type `{unitType}`,"
                        + $" property path: `{propPath}`, value: `{value}`");
                }
                object res;
                switch (propHead)
                {
                    case nameof(StatisticalUnit.Activities):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.ActivitiesUnits));
                        res = unit.ActivitiesUnits ?? new List<ActivityStatisticalUnit>();
                        ((ICollection<ActivityStatisticalUnit>) res).Add(
                            new ActivityStatisticalUnit {Activity = ParseActivity(propTail, value, null)});
                        break;
                    case nameof(StatisticalUnit.Persons):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                        res = unit.PersonsUnits ?? new List<PersonStatisticalUnit>();
                        ((ICollection<PersonStatisticalUnit>) res).Add(
                            new PersonStatisticalUnit {Person = ParsePerson(propTail, value, null)});
                        break;
                    case nameof(StatisticalUnit.Address):
                        res = ParseAddress(propTail, value, unit.Address);
                        break;
                    case nameof(StatisticalUnit.ActualAddress):
                        res = ParseAddress(propTail, value, unit.ActualAddress);
                        break;
                    case nameof(StatisticalUnit.ForeignParticipationCountry):
                        res = ParseCountry(propTail, value, unit.ForeignParticipationCountry);
                        break;
                    case nameof(StatisticalUnit.LegalForm):
                        res = ParseLegalForm(propTail, value, unit.LegalForm);
                        break;
                    case nameof(StatisticalUnit.InstSectorCode):
                        res = ParseSectorCode(propTail, value, unit.InstSectorCode);
                        break;
                    case nameof(StatisticalUnit.DataSourceClassification):
                        res = ParseDataSourceClassification(propTail, value, unit.DataSourceClassification);
                        break;
                    default:
                        var type = propInfo.PropertyType;
                        var underlyingType = Nullable.GetUnderlyingType(type);
                        res = value.HasValue() || underlyingType == null
                            ? Type.GetTypeCode(type) == TypeCode.String
                                ? value
                                : ConvertOrDefault(underlyingType ?? type, value)
                            : null;
                        break;
                }
                propInfo.SetValue(unit, res);
            }
        }
    }
}
