using Newtonsoft.Json;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Linq;
using static nscreg.Utilities.JsonPathHelper;

namespace nscreg.Business.DataSources
{
    public static class StatUnitKeyValueParser
    {
        public static readonly string[] StatisticalUnitArrayPropertyNames = new[] { nameof(StatisticalUnit.Activities), nameof(StatisticalUnit.Persons), nameof(StatisticalUnit.ForeignParticipationCountriesUnits) };

        public static string GetStatIdSourceKey(IEnumerable<(string source, string target)> mapping)
            => mapping.FirstOrDefault(vm => vm.target == nameof(StatisticalUnit.StatId)).source;

        public static void ParseAndMutateStatUnit(
            IReadOnlyDictionary<string, object> nextProps,
            StatisticalUnit unit)
        {
            foreach (var kv in nextProps)
            {

                if (kv.Value is string)
                {
                    try
                    {
                        UpdateObject(kv.Key, kv.Value);
                    }
                    catch (Exception ex)
                    {
                        ex.Data.Add("target property", kv.Key);
                        ex.Data.Add("value", kv.Value);
                        ex.Data.Add("unit", unit);
                        throw;
                    }
                }
                else if (kv.Value is List<KeyValuePair<string, Dictionary<string, string>>> arrayProperty)
                {
                    var targetArrKeys = arrayProperty.SelectMany(x=>x.Value.Select(d=>d.Key)).Distinct();
                    var mapping = targetArrKeys.ToDictionary(x => x, x => new string[] { x });
                    try
                    {
                        
                        UpdateObject(kv.Key, kv.Value, mapping);
                    }
                    catch (Exception ex)
                    {
                        ex.Data.Add("source property", kv.Key);
                        ex.Data.Add("target property", targetArrKeys);
                        ex.Data.Add("value", kv.Value);
                        ex.Data.Add("unit", unit);
                        throw;
                    }
                }
                else
                {
                    System.Diagnostics.Debug.Fail("Bad sector of code. NextProps: " + JsonConvert.SerializeObject(nextProps));
                }
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
                                        UpdateCollectionProperty((ICollection<ActivityStatisticalUnit>)propValue, ActivityIsNew, GetActivity, SetActivity, PropertyParser.ParseActivity, targetKey, activityValue.Value);
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
                                        UpdateCollectionProperty((ICollection<PersonStatisticalUnit>)propValue, PersonIsNew, GetPerson, SetPerson, PropertyParser.ParsePerson, targetKey, personValue.Value, PropertyParser.SetPersonStatUnitOwnPeroperties);
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
                        if (valueArr != null)
                            foreach (var countryFromArray in valueArr)
                            {
                                Country prev = new Country();
                                foreach (var countryValue in countryFromArray.Value)
                                {
                                    if (!mappingsArr.TryGetValue(countryValue.Key, out string[] targetKeys)) continue;
                                    foreach (var targetKey in targetKeys)
                                    {
                                        PropertyParser.ParseCountry(targetKey, countryValue.Value, prev);
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
                    case nameof(StatisticalUnit.Address):
                        propValue = PropertyParser.ParseAddress(propTail, value, unit.Address);
                        break;
                    case nameof(StatisticalUnit.ActualAddress):
                        propValue = PropertyParser.ParseAddress(propTail, value, unit.ActualAddress);
                        break;
                    case nameof(StatisticalUnit.PostalAddress):
                        propValue = PropertyParser.ParseAddress(propTail, value, unit.PostalAddress);
                        break;
                    case nameof(StatisticalUnit.LegalForm):
                        propValue = PropertyParser.ParseLegalForm(propTail, value, unit.LegalForm);
                        break;
                    case nameof(StatisticalUnit.InstSectorCode):
                        propValue = PropertyParser.ParseSectorCode(propTail, value, unit.InstSectorCode);
                        break;
                    case nameof(StatisticalUnit.DataSourceClassification):
                        propValue = PropertyParser.ParseDataSourceClassification(propTail, value, unit.DataSourceClassification);
                        break;
                    case nameof(StatisticalUnit.Size):
                        propValue = PropertyParser.ParseSize(propTail, value, unit.Size);
                        break;
                    case nameof(StatisticalUnit.UnitStatus):
                        propValue = PropertyParser.ParseUnitStatus(propTail, value, unit.UnitStatus);
                        break;
                    case nameof(StatisticalUnit.ReorgType):
                        propValue = PropertyParser.ParseReorgType(propTail, value, unit.ReorgType);
                        break;
                    case nameof(StatisticalUnit.RegistrationReason):
                        propValue = PropertyParser.ParseRegistrationReason(propTail, value, unit.RegistrationReason);
                        break;
                    case nameof(StatisticalUnit.ForeignParticipation):
                        propValue = PropertyParser.ParseForeignParticipation(propTail, value, unit.ForeignParticipation);
                        break;
                    default:
                        var type = propInfo.PropertyType;
                        var underlyingType = Nullable.GetUnderlyingType(type);
                        propValue = value.HasValue() || underlyingType == null
                            ? Type.GetTypeCode(type) == TypeCode.String
                                ? value
                                : PropertyParser.ConvertOrDefault(underlyingType ?? type, value)
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
                    if (!isOwnProperty)
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
