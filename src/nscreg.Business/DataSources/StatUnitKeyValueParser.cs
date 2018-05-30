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
            => mapping.FirstOrDefault(vm => vm.target == nameof(StatisticalUnit.StatId)).source;

        public static void ParseAndMutateStatUnit(
            IReadOnlyDictionary<string, string[]> mappings,
            IReadOnlyDictionary<string, string> nextProps,
            StatisticalUnit unit)
        {
            var aggregated = nextProps.Aggregate(new Dictionary<string, string>(), AggregateAllFlattenPropsToJson);
            foreach (var kv in aggregated)
            {
                if (!mappings.TryGetValue(kv.Key, out var targetKeys)) continue;
                foreach (var targetKey in targetKeys)
                {
                    try
                    {
                        UpdateObject(targetKey, kv.Value);
                    }
                    catch (Exception ex)
                    {
                        ex.Data.Add("source property", kv.Key);
                        ex.Data.Add("target property", targetKey);
                        ex.Data.Add("value", kv.Value);
                        ex.Data.Add("unit", unit);
                        throw;
                    }
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
                object propValue;
                switch (propHead)
                {
                    case nameof(StatisticalUnit.Activities):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.ActivitiesUnits));
                        propValue = unit.ActivitiesUnits ?? new List<ActivityStatisticalUnit>();
                        UpdateCollectionProperty((ICollection<ActivityStatisticalUnit>) propValue,
                            ActivityIsNew, GetActivity, SetActivity, ParseActivity, propTail, value);
                        break;
                    case nameof(StatisticalUnit.Persons):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                        propValue = unit.PersonsUnits ?? new List<PersonStatisticalUnit>();
                        UpdateCollectionProperty((ICollection<PersonStatisticalUnit>) propValue,
                            PersonIsNew, GetPerson, SetPerson, ParsePerson, propTail, value);
                        break;
                    case nameof(StatisticalUnit.ForeignParticipationCountry):
                        propValue = ParseCountry(propTail, value, unit.ForeignParticipationCountry);
                        break;
                    case nameof(StatisticalUnit.Address):
                        propValue = ParseAddress(propTail, value, unit.Address);
                        break;
                    case nameof(StatisticalUnit.ActualAddress):
                        propValue = ParseAddress(propTail, value, unit.ActualAddress);
                        break;
                    case nameof(StatisticalUnit.LegalForm):
                        propValue = ParseLegalForm(propTail, value, unit.LegalForm);
                        break;
                    case nameof(StatisticalUnit.InstSectorCode):
                        propValue = ParseSectorCode(propTail, value, unit.InstSectorCode);
                        break;
                    case nameof(StatisticalUnit.DataSourceClassification):
                        propValue = ParseDataSourceClassification(propTail, value, unit.DataSourceClassification);
                        break;
                    default:
                        var type = propInfo.PropertyType;
                        var underlyingType = Nullable.GetUnderlyingType(type);
                        propValue = value.HasValue() || underlyingType == null
                            ? Type.GetTypeCode(type) == TypeCode.String
                                ? value
                                : ConvertOrDefault(underlyingType ?? type, value)
                            : null;
                        break;
                }

                propInfo.SetValue(unit, propValue);

                void UpdateCollectionProperty<TJoin, TDependant>(
                    ICollection<TJoin> joinEntities,
                    Func<TJoin, bool> isJoinNew,
                    Func<TJoin, TDependant> getDependant,
                    Action<TJoin, TDependant> setDependant,
                    Func<string, string, TDependant, TDependant> parseDependant,
                    string propPath1, string propValue1) where TJoin : class
                {
                    var newJoin = joinEntities.LastOrDefault(isJoinNew);
                    var insertNew = newJoin == null;
                    if (insertNew) newJoin = Activator.CreateInstance<TJoin>();
                    setDependant(newJoin, parseDependant(propPath1, propValue1, getDependant(newJoin)));
                    if (insertNew) joinEntities.Add(newJoin);
                }

                bool ActivityIsNew(ActivityStatisticalUnit join) => join.ActivityId == 0 && join.Activity != null;

                Activity GetActivity(ActivityStatisticalUnit join) => join.Activity;

                void SetActivity(ActivityStatisticalUnit join, Activity dependant) => join.Activity = dependant;

                bool PersonIsNew(PersonStatisticalUnit join) =>
                    join.PersonId.GetValueOrDefault() == 0 && join.Person != null;

                Person GetPerson(PersonStatisticalUnit join) => join.Person;

                void SetPerson(PersonStatisticalUnit join, Person dependant)
                {
                    join.Person = dependant;
                    join.PersonType = dependant.Role;
                }
            }
        }
    }
}
