using Newtonsoft.Json;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using static nscreg.Utilities.JsonPathHelper;

namespace nscreg.Business.DataSources
{
    public static class StatUnitKeyValueParser
    {
        public static readonly string[] StatisticalUnitArrayPropertyNames = new[] { nameof(StatisticalUnit.Activities), nameof(StatisticalUnit.Persons), nameof(StatisticalUnit.ForeignParticipationCountriesUnits) };

        public static string GetStatIdSourceKey(IEnumerable<(string source, string target)> mapping)
            => mapping.FirstOrDefault(vm => vm.target == nameof(StatisticalUnit.StatId)).target;

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
                        var unitActivities = unit.ActivitiesUnits ?? new List<ActivityStatisticalUnit>();
                        var actPropValue = new List<ActivityStatisticalUnit>();
                        if (valueArr != null)
                            foreach (var activityFromArray in valueArr)
                            {
                                foreach (var activityValue in activityFromArray.Value)
                                {
                                    if (!mappingsArr.TryGetValue(activityValue.Key, out string[] targetKeys)) continue;
                                    foreach (var targetKey in targetKeys)
                                    {
                                        UpdateCollectionProperty(unitActivities, targetKey, activityValue.Value);
                                    }
                                }
                                actPropValue.AddRange(unitActivities);
                                unitActivities = new List<ActivityStatisticalUnit>();
                            }
                        propValue = actPropValue;

                        break;
                    case nameof(StatisticalUnit.Persons):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                        var persons = unit.PersonsUnits ?? new List<PersonStatisticalUnit>();
                        var tmpPropValue = new List<PersonStatisticalUnit>();
                        if (valueArr != null)
                            foreach (var personFromArray in valueArr)
                            {
                                foreach (var personValue in personFromArray.Value)
                                {
                                    if (!mappingsArr.TryGetValue(personValue.Key, out string[] targetKeys)) continue;
                                    foreach (var targetKey in targetKeys)
                                    {
                                        UpdateCollectionProperty(persons, targetKey, personValue.Value);

                                    }
                                }
                                tmpPropValue.AddRange(persons);
                                persons = new List<PersonStatisticalUnit>();
                            }
                        propValue = persons;
                        break;
                    case nameof(StatisticalUnit.ForeignParticipationCountriesUnits):
                        var fpcPropValue = new List<CountryStatisticalUnit>();
                        var foreignParticipationCountries = unit.ForeignParticipationCountriesUnits ?? new List<CountryStatisticalUnit>();
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
                                foreignParticipationCountries.Add(new CountryStatisticalUnit()
                                {
                                    CountryId = prev.Id,
                                    Country = prev
                                });
                                fpcPropValue.AddRange(foreignParticipationCountries);
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

                propInfo?.SetValue(unit, propValue);
            }
        }
        private static void UpdateCollectionProperty(ICollection<ActivityStatisticalUnit> activities, string targetKey, string value)
        {
            var newJoin = activities.LastOrDefault(x => x.ActivityId == 0 && x.Activity != null) ?? Activator.CreateInstance<ActivityStatisticalUnit>();

            newJoin.Activity = PropertyParser.ParseActivity(targetKey, value, newJoin.Activity);

            if (newJoin.Activity.ActivityType == ActivityTypes.Primary)
            {
                var existsActivity = activities.FirstOrDefault(x => x.Activity.ActivityType == ActivityTypes.Primary);

                if(existsActivity?.Activity?.ActivityYear < newJoin.Activity?.ActivityYear)
                {
                    existsActivity.Activity = newJoin.Activity;
                }
            }
            else
            {
                activities.Add(newJoin);
            }
            
        }
        private static void UpdateCollectionProperty(ICollection<PersonStatisticalUnit> persons, string targetKey, string value)
        {
            var newJoin = persons.LastOrDefault(x => x.PersonId.Value == 0 && x.Person != null) ?? new PersonStatisticalUnit();

            var isOwnProperty = PropertyParser.SetPersonStatUnitOwnProperties(targetKey, newJoin, value);

            if (!isOwnProperty)
                PropertyParser.ParsePerson(targetKey, value, newJoin.Person);

            var newPersons = new List<PersonStatisticalUnit>();
            foreach (var existsPerson in persons)
            {
                if (existsPerson.Person.Role == newJoin.Person.Role)
                {
                    existsPerson.Person = newJoin.Person;
                }
                else
                {
                    newPersons.Add(newJoin);
                }
            }
            persons.AddRange(newPersons);
        }

    }
}
