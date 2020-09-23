using FluentAssertions;
using nscreg.Business.Test.Base;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.DataSources;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;
using Activity = nscreg.Data.Entities.Activity;

namespace nscreg.Business.Test.DataSources
{
    public class PopulateServiceTest : BaseTest
    {
        public PopulateServiceTest(ITestOutputHelper helper) : base(helper)
        {

        }
        private (string, string)[] GetArrayMappingByString(string mapping)
        {
            return mapping.Split(',')
                .Select(vm =>
                {
                    var pair = vm.Split('-');
                    return (pair[0], pair[1]);
                }).ToArray();
        }

        [Fact]
        public async Task PopulateAsync_PersonMapping_Success()
        {
            var mappings =
    "statId-StatId,name-Name,activity1-Activities.Activity.ActivityCategory.Code,employees-Activities.Activity.Employees,activityYear-Activities.Activity.ActivityYear,addr1-Address.AddressPart1,PersonRole-Persons.Person.Role,PersonGivenName-Persons.Person.GivenName,PersonSurname-Persons.Person.Surname,PersonSex-Persons.Person.Sex";

            var personType = new PersonType() { Name = "DIRECTOR", Id = 0 };

            DatabaseContext.PersonTypes.Add(personType);
            await DatabaseContext.SaveChangesAsync();
            var unit = new LegalUnit
            {
                Name = "LAST FRIDAY INVEST AS",
                StatId = "920951287",
                Address = new Address()
                {
                    AddressPart1 = "TEST ADDRESS"
                },
                PersonsUnits = new List<PersonStatisticalUnit>()
                    {
                        new PersonStatisticalUnit()
                        {
                            Person = new Person()
                            {
                                GivenName = "Vasya",
                                Surname = "Vasin",
                                Sex = 1,
                                Role = personType.Id,
                            }
                        }
                    },
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                    {
                        new ActivityStatisticalUnit()
                        {
                            Activity = new Activity()
                            {
                                ActivityCategory = new ActivityCategory()
                                {
                                    Code = "62.020"
                                },
                                Employees = 100,
                                ActivityYear = 2019
                            }
                        },
                        new ActivityStatisticalUnit()
                        {
                            Activity = new Activity()
                            {
                                ActivityCategory = new ActivityCategory()
                                {
                                    Code = "70.220"
                                },
                                Employees = 20,
                                ActivityYear = 2018
                            }
                        }
                    }
            };
            var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, DatabaseContext);

            var raw = new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                    { "Address.AddressPart1", "TEST ADDRESS" },
                    { "Persons", new List<KeyValuePair<string, Dictionary<string, string>>>(){
                        new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                            {
                                {"Role", "Director"},
                                {"GivenName", "Vasya" },
                                {"Surname", "Vasin" },
                                {"Sex", "1" }
                            })
                        }
                    },
                    { "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>()
                        {
                            new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                            {
                                {"ActivityCategory.Code", "62.020"},
                                {"Employees","100"},
                                {"ActivityYear","2019"}
                            }),
                            new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                            {
                                {"ActivityCategory.Code", "70.220"},
                                {"Employees","20"},
                                {"ActivityYear","2018"}
                            })
                        }
                    }
                };
            var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);

            popUnit.Should().BeEquivalentTo(unit);
        }

        [Fact]
        public async Task PopulateAsync_NewObjectOnAlter_ReturnsError()
        {
            var unitMapping = "TestStatId-StatId,Name-Name";

            var raw = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"},
            };

            var populateService = new PopulateService(GetArrayMappingByString(unitMapping), DataSourceAllowedOperation.Alter, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, DatabaseContext);
            var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);

            errors.Should().Be($"StatUnit failed with error: {Resource.StatUnitIdIsNotFound} ({popUnit.StatId})",
                $"Stat unit with StatId {popUnit.StatId} doesn't exist in database");

        }

        [Fact]
        public async Task PopulateAsync_ExistsObjectOnCreate_ReturnsError()
        {
            var mappings = "StatId-StatId,Name-Name";

            var keyValueDict = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"}
            };

            DatabaseContext.StatisticalUnits.Add(new LegalUnit()
            {
                StatId = "920951287",
                Name = "LAST FRIDAY INVEST AS"
            });
            await DatabaseContext.SaveChangesAsync();
            var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, DatabaseContext);
            var (popUnit, _, error) = await populateService.PopulateAsync(keyValueDict);

            error.Should().Be(string.Format(Resource.StatisticalUnitWithSuchStatIDAlreadyExists, popUnit.StatId),
                $"Stat unit with StatId - {popUnit.StatId} exist in database");

        }

        [Fact]
        public async Task PopulateAsync_ObjectWithActivitiesOnCreate_ReturnsPopulatedObject()
        {
            var mappings =
                "StatId-StatId," +
                "Name-Name," +
                "Activities.Activity.ActivityYear-Activities.Activity.ActivityYear," +
                "Activities.Activity.CategoryCode-Activities.Activity.ActivityCategory.Code," +
                "Activities.Activity.Employees-Activities.Activity.Employees";

            var raw = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"},
                { "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>
                    {
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear","2019"},
                            {"ActivityCategory.Code", "62.020"},
                            {"Employees","100"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityCategory.Code", "68.209"},
                        })
                    }
                }

            };
            var unit = new LegalUnit()
            {
                StatId = "920951287",
                Name = "LAST FRIDAY INVEST AS",
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                {
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityYear = 2019,
                            Employees = 100,
                            ActivityCategory =  new ActivityCategory()
                            {
                                Code = "62.020"
                            }
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityCategory = new ActivityCategory()
                            {
                                Code = "68.209"
                            }
                        }
                    }
                }
            };

            var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, DatabaseContext);
            var (popUnit, isNew, errors) = await populateService.PopulateAsync(raw);

            popUnit.Should().BeEquivalentTo(unit);


        }

        [Fact]
        public async Task PopulateAsync_ObjectWithActivitiesOnCreate_ReturnsPopulatedObjectWithMappedExistsActivities()
        {
            var mappings =
                "StatId-StatId,Name-Name,Activities.Activity.ActivityYear-Activities.Activity.ActivityYear,Activities.Activity.CategoryCode-Activities.Activity.ActivityCategory.Code,Activities.Activity.Employees-Activities.Activity.Employees";

            var raw = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"},
                { "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>
                {
                    new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                    {
                        {"ActivityYear","2019"},
                        {"ActivityCategory.Code", "62.020"},
                        {"Employees","100"},

                    }),
                    new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                    {
                        {"ActivityCategory.Code", "68.209"},
                    })
                }}

            };
            var unit = new LegalUnit()
            {
                StatId = "920951287",
                Name = "LAST FRIDAY INVEST AS",
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                {
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityYear = 2019,
                            Employees = 100,
                            ActivityCategory =  new ActivityCategory()
                            {
                                Id = 1,
                                Code = "62.020"
                            },
                            ActivityCategoryId = 1
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityCategory = new ActivityCategory()
                            {
                                Id = 2,
                                Code = "68.209"
                            },
                            ActivityCategoryId = 2
                        }
                    },
                }
            };
            DatabaseContext.Activities.AddRange(
                new Activity()
                {
                    ActivityYear = 2020,
                    Employees = 1800,
                    ActivityCategory = new ActivityCategory()
                    {
                        Code = "62.020"
                    },
                },
                new Activity()
                {
                    ActivityYear = 2019,
                    Employees = 800,
                    ActivityCategory = new ActivityCategory()
                    {
                        Code = "68.209"
                    },
                });
            await DatabaseContext.SaveChangesAsync();

            var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, DatabaseContext);
            var (popUnit, isNew, errors) = await populateService.PopulateAsync(raw);

            popUnit.Should().BeEquivalentTo(unit);
        }

        [Fact]
        public async Task PopulateAsync_ObjectWithActivitiesOnCreateOrAlter_ReturnsPopulatedObject()
        {
            var mappings =
                "StatId-StatId,Name-Name,Activities.Activity.ActivityYear-Activities.Activity.ActivityYear,Activities.Activity.CategoryCode-Activities.Activity.ActivityCategory.Code,Activities.Activity.Employees-Activities.Activity.Employees";

            var raw = new Dictionary<string, object>()
            {
                {"StatId", "9209512871"},
                {"Name", "LAST FRIDAY INVEST AS"},
                {
                    "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>
                    {
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear", "2020"},
                            {"ActivityCategory.Code", "67.111"},
                            {"Employees", "10"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear", "2019"},
                            {"ActivityCategory.Code", "62.020"},
                            {"Employees", "1000"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityCategory.Code", "68.209"},
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear", "2021"},
                            {"ActivityCategory.Code", "68.209"},
                        }),
                    }
                }
            };

            Dictionary<string, ActivityCategory> categories = new Dictionary<string, ActivityCategory>();
            categories.Add("67.111", new ActivityCategory()
            {
                Code = "67.111"
            });
            categories.Add("62.020", new ActivityCategory()
            {
                Code = "62.020"
            });
            categories.Add("68.209", new ActivityCategory()
            {
                Code = "68.209"
            });

            DatabaseContext.ActivityCategories.AddRange(categories.Values);
            await DatabaseContext.SaveChangesAsync();

            var dbUnit = new LegalUnit()
            {
                StatId = "9209512871",
                Name = "TEST TEST",
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                {
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2020,
                            Employees = 1,
                            ActivityCategory = categories["67.111"]
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2019,
                            Employees = 2,
                            ActivityCategory = categories["62.020"]
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Secondary,
                            ActivityYear = 2019,
                            Employees = 1000,
                            ActivityCategory = categories["68.209"]
                        }
                    }
                }
            };
            DatabaseContext.StatisticalUnits.Add(dbUnit);
            await DatabaseContext.SaveChangesAsync();

            var resultUnit = new LegalUnit()
            {
                RegId = 1,
                StatId = "9209512871",
                Name = "LAST FRIDAY INVEST AS",
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                {
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2020,
                            Employees = 10,
                            ActivityCategory = categories["67.111"],
                            ActivityCategoryId = categories["67.111"].Id,
                        }
                    },
                    new ActivityStatisticalUnit()
                    {

                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2019,
                            Employees = 1000,
                            ActivityCategory = categories["62.020"],
                            ActivityCategoryId = categories["62.020"].Id
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Secondary,
                            ActivityYear = 2019,
                            Employees = 1000,
                            ActivityCategory = categories[ "68.209"],
                            ActivityCategoryId = categories[ "68.209"].Id
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2021,
                            ActivityCategory = categories[ "68.209"],
                            ActivityCategoryId = categories[ "68.209"].Id
                        }
                    }
                }
            };

            var populateService = new PopulateService(GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit,
                DatabaseContext);
            var (popUnit, isNew, errors) = await populateService.PopulateAsync(raw);

            popUnit.ActivitiesUnits.Should().BeEquivalentTo(resultUnit.ActivitiesUnits,
                op => op.Excluding(x => x.Unit).Excluding(x => x.UnitId).Excluding(x => x.ActivityId)
                    .Excluding(x => x.Activity.ActivitiesUnits).Excluding(x => x.Activity.Id));
        }

    }
}
