using FluentAssertions;
using nscreg.Business.Test.Base;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common;
using nscreg.TestUtils;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace nscreg.Business.Test.DataSources
{
    public class PopulateServiceTest : BaseTest
    {
        public PopulateServiceTest(ITestOutputHelper helper) : base(helper)
        {
        }

        [Fact]
        public async Task PopulateAsync_PersonMapping_Success()
        {
            var mappings =
    "statId-StatId,name-Name,activity1-Activities.Activity.ActivityCategory.Code,employees-Activities.Activity.Employees,activityYear-Activities.Activity.ActivityYear,addr1-Address.AddressPart1,PersonRole-Persons.Person.Role";

            var mappingsArray = mappings.Split(',').Select(vm =>
            {
                var pair = vm.Split('-');
                return (pair[0], pair[1]);
            }).ToArray();

            using (var context = InMemoryDb.CreateDbContext())
            {
                context.PersonTypes.Add(new PersonType { Name = "DIRECTOR" });
                await context.SaveChangesAsync();

                var populateService = new PopulateService(mappingsArray, DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);

                var raw = new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                    { "Address.AddressPart1", "TEST ADDRESS" },
                    { "Persons", new List<KeyValuePair<string, Dictionary<string, string>>>(){
                        new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                            {
                                {"Role", "Director"},
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
                            }),
                            new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                            {
                                {"ActivityCategory.Code", "52.292"},
                                {"Employees","10"}
                            }),
                            new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                            {
                                {"ActivityCategory.Code", "68.209"},
                            })
                        }
                    }
                };


                var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);


            }
        }

        [Fact]
        public async Task PopulateAsync_NewObjectOnAlter_ReturnsError()
        {
            var unitMapping = "StatId-StatId,Name-Name";

            var raw = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"},
            };

            using (var context = InMemoryDb.CreateDbContext())
            {
                var populateService = new PopulateService(GetArrayMappingByString(unitMapping), DataSourceAllowedOperation.Alter, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);
                var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);
                errors.Should().Be($"StatUnit failed with error: {Resource.StatUnitIdIsNotFound} ({popUnit.StatId})",
                    $"Stat unit with StatId {popUnit.StatId} doesn't exist in database");
            }
            
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
           

            using (var context = InMemoryDb.CreateDbContext())
            {
                var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);
                var (popUnit, _, error) = await populateService.PopulateAsync(keyValueDict);

                error.Should().Be(string.Format(Resource.StatisticalUnitWithSuchStatIDAlreadyExists, popUnit.StatId),
                    $"Stat unit with StatId - {popUnit.StatId} exist in database");
            }

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
            using (var context = InMemoryDb.CreateDbContext())
            {
                var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);
                var (popUnit, isNew, errors) = await populateService.PopulateAsync(raw);

                popUnit.Should().BeEquivalentTo(unit);
            }

        }

        [Fact]
        public async Task PopulateAsync_ObjectWithActivitiesOnAlter_ReturnsPopulatedObjectWithMappedExistsActivities()
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
                            Id = 1,
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
                            Id = 2,
                            ActivityCategory = new ActivityCategory()
                            {
                                Id = 2,
                                Code = "68.209"
                            },
                            ActivityCategoryId = 2
                        }
                    }
                }
            };
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.Activities.AddRange(
                new Activity
                {
                    ActivityYear = 2028,
                    Employees = 400,
                    ActivityCategory = new ActivityCategory
                    {
                        Code = "62.020"
                    }
                },
                new Activity
                {
                    ActivityYear = 2020,
                    Employees = 500,
                    ActivityCategory = new ActivityCategory()
                     {
                         Code = "68.209"
                     }
                });
                await context.SaveChangesAsync();
                var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);
                var (popUnit, isNew, errors) = await populateService.PopulateAsync(raw);

                popUnit.Should().BeEquivalentTo(unit);
            }

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




    }
}
