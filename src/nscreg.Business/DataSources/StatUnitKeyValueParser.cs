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
            IReadOnlyDictionary<string, object> nextProps,
            StatisticalUnit unit)
        {
            var aggregated = nextProps.Aggregate(new Dictionary<string, object>(), AggregateAllFlattenPropsToJson);
            foreach (var kv in aggregated)
            {
                
                if (kv.Value is string)
                {
                    if (!mappings.TryGetValue(kv.Key, out string[] targetKeys) && kv.Value is string) continue;
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
                else
                {
                    var mappingArray = mappings.Where(x => x.Key.StartsWith($"{kv.Key}."));
                    var targetArrKeys = mappingArray.ToDictionary(x=>x.Key.Split('.').LastOrDefault(),x=>x.Value.Select(d=>d.Split('.').LastOrDefault()).ToArray());
                    string keyClassName = mappingArray.FirstOrDefault().Value.FirstOrDefault().Split('.').FirstOrDefault();
                    UpdateObject(keyClassName, kv.Value, targetArrKeys);
                }
            }

            Dictionary<string, object> AggregateAllFlattenPropsToJson(
                Dictionary<string, object> accumulation,
                KeyValuePair<string, object> cur)
            {
                if (!cur.Key.Contains('.'))
                {
                    accumulation.Add(cur.Key, cur.Value);
                    return accumulation;
                }
                var topKey = cur.Key.Split('.')[0];
                if (!accumulation.TryGetValue(topKey, out var previous)) previous = "{}";
                if (previous is string s)
                    accumulation[topKey] = ReplacePath(s, cur.Key, cur.Value);
                return accumulation;
            }

            void UpdateObject(string propPath, object inputValue,
                Dictionary<string, string[]> mappingsArr = null)
            {
                var propHead = PathHead(propPath);
                var propTail = PathTail(propPath);
                var unitType = unit.GetType();
                var propInfo = unitType.GetProperty(propHead);
                if (propInfo == null)
                {
                    throw new Exception(
                        $"Property `{propHead}` not found in type `{unitType}`,"
                        + $" property path: `{propPath}`, value: `{inputValue}`");
                }
                object propValue;
                string value = "";
                List<KeyValuePair<string, Dictionary<string, string>>> valueArr = null;
                if (inputValue is string s)
                {
                    value = s;
                }
                else
                {
                    valueArr = inputValue as List<KeyValuePair<string, Dictionary<string, string>>>;
                }
                switch (propHead)
                {
                    case nameof(StatisticalUnit.Activities):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.ActivitiesUnits));
                        propValue = unit.ActivitiesUnits ?? new List<ActivityStatisticalUnit>();
                        var actPropValue = new List<ActivityStatisticalUnit>();
                        if (valueArr != null)
                            foreach (var activityFromArray in valueArr)
                            {
                                foreach (var activityValue in activityFromArray.Value)
                                {
                                    if (!mappingsArr.TryGetValue(activityValue.Key, out string[] targetKeys)) continue;
                                    foreach (var targetKey in targetKeys)
                                    {
                                        UpdateCollectionProperty((ICollection<ActivityStatisticalUnit>)propValue, ActivityIsNew, GetActivity, SetActivity, ParseActivity, targetKey, activityValue.Value);
                                    }
                                }
                                actPropValue.AddRange((ICollection<ActivityStatisticalUnit>)propValue);
                                propValue = Activator.CreateInstance<List<ActivityStatisticalUnit>>();
                            }
                        propValue = actPropValue;
                        break;
                    case nameof(StatisticalUnit.Persons):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                        propValue = unit.PersonsUnits ?? new List<PersonStatisticalUnit>();
                        var tmpPropValue = new List<PersonStatisticalUnit>();
                        if (valueArr != null)
                            foreach (var personFromArray in valueArr)
                            {
                                foreach (var personValue in personFromArray.Value)
                                {
                                    if (!mappingsArr.TryGetValue(personValue.Key, out string[] targetKeys)) continue;
                                    foreach (var targetKey in targetKeys)
                                    {
                                        UpdateCollectionProperty((ICollection<PersonStatisticalUnit>)propValue, PersonIsNew, GetPerson, SetPerson, ParsePerson, targetKey, personValue.Value, SetPersonStatUnitOwnPeroperties);
                                    }
                                }
                                tmpPropValue.AddRange((ICollection<PersonStatisticalUnit>)propValue);
                                propValue = Activator.CreateInstance<List<PersonStatisticalUnit>>();
                            }
                        propValue = tmpPropValue;
                        break;
                    case nameof(StatisticalUnit.ForeignParticipationCountriesUnits):
                        var fpcPropValue = new List<CountryStatisticalUnit>();
                        propValue = unit.ForeignParticipationCountriesUnits ?? new List<CountryStatisticalUnit>();
                        if (valueArr!=null)
                            foreach (var countryFromArray in valueArr)
                            {
                                Country prev = new Country();
                                foreach (var countryValue in countryFromArray.Value)
                                {
                                    if (!mappingsArr.TryGetValue(countryValue.Key, out string[] targetKeys)) continue;
                                    foreach (var targetKey in targetKeys)
                                    {
                                        ParseCountry(targetKey, countryValue.Value, prev);
                                    }
                                }
                                ((ICollection<CountryStatisticalUnit>)propValue).Add(new CountryStatisticalUnit()
                                {
                                    CountryId = prev.Id,
                                    Country = prev
                                });
                                fpcPropValue.AddRange((ICollection<CountryStatisticalUnit>)propValue);
                                propValue = Activator.CreateInstance<List<CountryStatisticalUnit>>();
                            }
                        propValue = fpcPropValue;
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
                    case nameof(StatisticalUnit.PostalAddress):
                        propValue = ParseAddress(propTail, value, unit.PostalAddress);
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
                    case nameof(StatisticalUnit.Size):
                        propValue = ParseSize(propTail, value, unit.Size);
                        break;
                    case nameof(StatisticalUnit.UnitStatus):
                        propValue = ParseUnitStatus(propTail, value, unit.UnitStatus);
                        break;
                    case nameof(StatisticalUnit.ReorgType):
                        propValue = ParseReorgType(propTail, value, unit.ReorgType);
                        break;
                    case nameof(StatisticalUnit.RegistrationReason):
                        propValue = ParseRegistrationReason(propTail, value, unit.RegistrationReason);
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
                    string propPath1, string propValue1,
                    Func<string, TJoin, string, bool> setOwnProperties = null) where TJoin : class
                {
                    var newJoin = joinEntities.LastOrDefault(isJoinNew);
                    var insertNew = newJoin == null;
                    if (insertNew) newJoin = Activator.CreateInstance<TJoin>();
                    bool isOwnProperty = false;
                    if (setOwnProperties != null)
                    {
                        isOwnProperty = setOwnProperties(propPath1, newJoin, propValue1);
                    }                        
                    if(!isOwnProperty)
                        setDependant(newJoin, parseDependant(propPath1, propValue1, getDependant(newJoin)));
                    if (insertNew) joinEntities.Add(newJoin);
                }

                bool ActivityIsNew(ActivityStatisticalUnit join) => join.ActivityId == 0 && join.Activity != null;
                Activity GetActivity(ActivityStatisticalUnit join) => join.Activity;
                void SetActivity(ActivityStatisticalUnit join, Activity dependant) => join.Activity = dependant;

                bool PersonIsNew(PersonStatisticalUnit join) => join.PersonId.GetValueOrDefault() == 0 && join.Person != null;
                Person GetPerson(PersonStatisticalUnit join) => join.Person;
                void SetPerson(PersonStatisticalUnit join, Person dependant) => join.Person = dependant;
            }
        }
    }
}
