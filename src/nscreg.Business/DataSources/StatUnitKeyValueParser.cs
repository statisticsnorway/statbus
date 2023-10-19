using Newtonsoft.Json;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Utilities;
using static nscreg.Utilities.JsonPathHelper;
using Activity = nscreg.Data.Entities.Activity;
using Person = nscreg.Data.Entities.Person;

namespace nscreg.Business.DataSources
{
    public static class StatUnitKeyValueParser
    {
        public static readonly string[] StatisticalUnitArrayPropertyNames = { nameof(StatisticalUnit.Activities), nameof(StatisticalUnit.Persons), nameof(StatisticalUnit.ForeignParticipationCountriesUnits) };

        public static string GetStatIdMapping(IEnumerable<(string source, string target)> mapping)
            => mapping.FirstOrDefault(vm => vm.target == nameof(StatisticalUnit.StatId)).target;

        public static void ParseAndMutateStatUnit(
            IReadOnlyDictionary<string, object> nextProps,
            StatisticalUnit unit, NSCRegDbContext context, string userId, DataAccessPermissions permissions, bool personsGooQuality)
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
                        bool hasAccess = true;
                        switch (unit)
                        {
                            case  LegalUnit _:
                                hasAccess = HasAccess<LegalUnit>(permissions, v => v.Activities);
                                break;
                            case LocalUnit _:
                                hasAccess = HasAccess<LocalUnit>(permissions, v => v.Activities);
                                break;
                            case EnterpriseUnit _:
                                hasAccess = HasAccess<EnterpriseUnit>(permissions, v => v.Activities);
                                break;
                        }
                        if (!hasAccess)
                            throw new Exception("You have no rights to change activities");
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.ActivitiesUnits));
                        var unitActivities = unit.ActivitiesUnits ?? new List<ActivityStatisticalUnit>();
                        if (valueArr != null)
                            UpdateActivities(unitActivities, valueArr, mappingsArr, userId);
                        propValue = unitActivities.Where(x => x.Activity.ActivityCategory?.Code != null || x.Activity.ActivityCategory?.Name != null).ToList();
                        break;
                    case nameof(StatisticalUnit.Persons):
                        propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                        var persons = unit.PersonsUnits ?? new List<PersonStatisticalUnit>();
                        unit.PersonsUnits?.ForEach(x => x.Person.Role = x.PersonTypeId);
                        if (valueArr != null)
                            UpdatePersons(persons, valueArr, mappingsArr, context, personsGooQuality);
                        propValue = persons;
                        break;
                    case nameof(StatisticalUnit.ForeignParticipationCountriesUnits):
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
                            }
                        propValue = foreignParticipationCountries;
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
            }
        }
        private static void UpdateActivities(ICollection<ActivityStatisticalUnit> dbActivities, List<KeyValuePair<string,Dictionary<string, string>>> importActivities, Dictionary<string, string[]> mappingsArr, string userId)
        {
            var defaultYear = DateTime.Now.Year - 1;
            var propPathActivityCategoryCode = string.Join(".", nameof(ActivityCategory), nameof(ActivityCategory.Code));
            var dbActivitiesGroups = dbActivities.GroupBy(x => x.Activity.ActivityYear).ToList();
            var importActivitiesGroups =
                importActivities.GroupBy(x => int.TryParse(x.Value.GetValueOrDefault(nameof(Activity.ActivityYear)), out int val) ? (int?)val : defaultYear).ToList();

            foreach (var importActivitiesGroup in importActivitiesGroups)
            {
                var dbGroup = dbActivitiesGroups.FirstOrDefault(x => x.Key == importActivitiesGroup.Key);
                if (dbGroup == null)
                {
                   var parsedActivities =  importActivitiesGroup.Select((x,i) => new ActivityStatisticalUnit
                   {
                       Activity = ParseActivityByTargetKeys(null, x.Value, mappingsArr, i == 0 ? ActivityTypes.Primary : ActivityTypes.Secondary, userId, defaultYear)
                   });
                   dbActivities.AddRange(parsedActivities);
                   continue;
                }

                importActivitiesGroup.GroupJoin(dbGroup,
                    import => import.Value.GetValueOrDefault(propPathActivityCategoryCode),
                    db => db.Activity.ActivityCategory.Code, (importRow, dbRows) => (importRow: importRow, dbRows: dbRows))
                    .ForEach(x =>
                    {
                        var dbRow = x.dbRows.FirstOrDefault();
                        if (dbRow != null)
                        {
                            dbRow.Activity = ParseActivityByTargetKeys(dbRow.Activity, x.importRow.Value, mappingsArr, ActivityTypes.Secondary, userId, defaultYear);
                        }
                        else
                        {
                            dbRow = new ActivityStatisticalUnit
                            {
                                Activity = ParseActivityByTargetKeys(null, x.importRow.Value, mappingsArr, ActivityTypes.Secondary, userId, defaultYear)
                            };
                            dbActivities.Add(dbRow);
                        }
                    });
            }
        }

        private static Activity ParseActivityByTargetKeys(Activity activity, Dictionary<string, string> targetKeys,
            Dictionary<string, string[]> mappingsArr, ActivityTypes defaultType, string userId, int defaultYear)
        {
            var activityTypeWasSet = activity != null;
            activity = activity ?? new Activity();
            foreach (var (key, val) in targetKeys)
            {
                if (!mappingsArr.TryGetValue(key, out var targetValues)) continue;
                foreach (var targetKey in targetValues)
                {
                    if (targetKey == nameof(Activity.ActivityType))
                    {
                        activityTypeWasSet = true;
                    }
                    activity = PropertyParser.ParseActivity(targetKey, val, activity);
                }
            }
            if (!activityTypeWasSet)
            {
                activity.ActivityType = defaultType;
            }
            activity.UpdatedBy = userId;
            activity.ActivityYear = activity.ActivityYear ?? defaultYear;
            activity.IdDate = DateTime.Now;
            activity.UpdatedDate = activity.Id == 0 ? DateTime.MaxValue : DateTime.Now;
            return activity;
        }

        private static Person ParsePersonByTargetKeys(Dictionary<string, string> targetKeys,
            Dictionary<string, string[]> mappingsArr, NSCRegDbContext context)
        {
            Person person = new Person();
            foreach (var (key,value) in targetKeys)
            {
                if(!mappingsArr.TryGetValue(key, out var targetValues)) continue;
                foreach (var targetKey in targetValues)
                {
                    if (targetKey == nameof(Person.Role))
                    {
                        var roleValue = value.ToLower();

                        var roleType = context.PersonTypes.Local.FirstOrDefault(x =>
                            x.Name.ToLower() == roleValue || x.NameLanguage1.HasValue() && x.NameLanguage1.ToLower() == roleValue ||
                            x.NameLanguage2.HasValue() && x.NameLanguage2.ToLower() == roleValue);

                        person = PropertyParser.ParsePerson(targetKey, roleType?.Id.ToString(), person, value);
                        continue;
                    }
                    person = PropertyParser.ParsePerson(targetKey, value, person);
                }
            }
            return person;
        }

        private static void UpdatePersons(ICollection<PersonStatisticalUnit> personsDb,
            List<KeyValuePair<string, Dictionary<string, string>>> importPersons,
            Dictionary<string, string[]> mappingsArr, NSCRegDbContext context, bool personsGoodQuality)
        {
            var newPersonStatUnits = importPersons.Select(person => ParsePersonByTargetKeys(person.Value, mappingsArr, context)).Select(newPerson => new PersonStatisticalUnit() { Person = newPerson, PersonTypeId = newPerson.Role }).ToList();
            if (personsGoodQuality)
            {
                var personsWithPersonalId = newPersonStatUnits.Where(x => x.Person.PersonalId != null).ToList();

                var personsForRemove = new List<PersonStatisticalUnit>();

                personsWithPersonalId.GroupJoin(personsDb, person => person.Person.PersonalId, dbPerson => dbPerson.Person.PersonalId, ((person, dbPersons) => (person: person, dbPersons: dbPersons))).ForEach(x =>
                {
                    if (!x.dbPersons.Any())
                    {
                        return;
                    }
                    x.dbPersons.ForEach(item =>
                    {
                        item.PersonTypeId = x.person.PersonTypeId;
                        MapPerson(item.Person, x.person.Person);
                    });
                    personsForRemove.Add(x.person);
                });

                RemoveInNewPersonsAndClearDeleted(newPersonStatUnits, personsForRemove);

                var personsWithBirthAndName = newPersonStatUnits.Where(x =>
                    x.Person.BirthDate != null && x.Person.GivenName != null && x.Person.Surname != null).ToList();

                var personsForAdd = new List<PersonStatisticalUnit>();
                personsWithBirthAndName.GroupJoin(personsDb, item => (item.Person.BirthDate, item.Person.GivenName, item.Person.Surname), dbItem => (dbItem.Person.BirthDate, dbItem.Person.GivenName, dbItem.Person.Surname), (person, dbPersons) => (person: person, dbPersons: dbPersons)).ForEach(
                    x =>
                    {
                        if (!x.dbPersons.Any())
                        {
                            personsForAdd.Add(x.person);
                        }
                        x.dbPersons.ForEach(item =>
                        {
                            item.PersonTypeId = x.person.PersonTypeId;
                            MapPerson(item.Person, x.person.Person);
                        });
                        personsForRemove.Add(x.person);
                    });

                personsDb.AddRange(personsForAdd);

                RemoveInNewPersonsAndClearDeleted(newPersonStatUnits, personsForRemove);

                personsDb.AddRange(newPersonStatUnits);
            }

            personsDb.AddRange(newPersonStatUnits);
            

        }

        private static void MapPerson(Person oldPerson, Person newPerson)
        {
            oldPerson.Role = newPerson.Role ?? oldPerson.Role;
            oldPerson.BirthDate = newPerson.BirthDate ?? oldPerson.BirthDate;
            oldPerson.NationalityCode = newPerson.NationalityCode ?? oldPerson.NationalityCode;
            oldPerson.Surname = newPerson.Surname ?? oldPerson.Surname;
            oldPerson.MiddleName = newPerson.MiddleName ?? oldPerson.MiddleName;
            oldPerson.GivenName = newPerson.GivenName ?? oldPerson.GivenName;
            oldPerson.PhoneNumber = newPerson.PhoneNumber ?? oldPerson.PhoneNumber;
            oldPerson.Sex = newPerson.Sex ?? oldPerson.Sex;
        }

        private static void RemoveInNewPersonsAndClearDeleted(List<PersonStatisticalUnit> newPerson, List<PersonStatisticalUnit> deleteList)
        {
            foreach (var element in deleteList)
            {
                newPerson.Remove(element);
            }
            deleteList.Clear();
        }

        private static bool HasAccess<T>(DataAccessPermissions dataAccess, Expression<Func<T, object>> property) =>
            dataAccess.HasWritePermission(
                DataAccessAttributesHelper.GetName<T>(ExpressionUtils.GetExpressionText(property)));
    }
}
