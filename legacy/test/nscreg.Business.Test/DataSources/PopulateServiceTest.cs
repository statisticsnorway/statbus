using System;
using FluentAssertions;
using nscreg.Business.Test.Base;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.DataSources;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Common.Services;
using Xunit;
using Xunit.Abstractions;
using Activity = nscreg.Data.Entities.Activity;

namespace nscreg.Business.Test.DataSources
{
    public class PopulateServiceTest : BaseTest
    {
        private static IMapper CreateMapper() => new MapperConfiguration(mc =>
            mc.AddMaps(typeof(Startup).Assembly)).CreateMapper();

        public static object locker = new object();
        public PopulateServiceTest(ITestOutputHelper helper) : base(helper)
        {
            lock (locker)
            {
                //Mapper.Reset();


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

        [Fact]
        public async Task PopulateAsync_PersonMapping_Success()
        {
            var mappings = "StatId-StatId,Name-Name";

            var personTypes = new PersonType() {Name = "OWNER"};
            await DatabaseContext.AddAsync(personTypes);
            await DatabaseContext.SaveChangesAsync();
            await DatabaseContext.PersonTypes.LoadAsync();
            var dateTimeToday = DateTime.Today;

            var dbunit = new LegalUnit
            {
                UserId = "42",
                Name = "LAST FRIDAY INVEST AS",
                StatId = "920951287",
                PersonsUnits = new List<PersonStatisticalUnit>()
                    {
                        new PersonStatisticalUnit()
                        {
                            Person = new Person()
                            {
                                PersonalId = "1",
                                GivenName = "Vasya",
                                Surname = "Vasin",
                                BirthDate = dateTimeToday,
                                Sex = 1,
                                PhoneNumber = "12345"
                            }
                        },
                        new PersonStatisticalUnit()
                        {
                            Person = new Person()
                            {
                                GivenName = "Vasya12345",
                                Surname = "Vasin12345",
                                BirthDate = dateTimeToday,
                                Sex = 1,
                            }
                        },
                    }
            };
            var raw = new Dictionary<string, object>()
            {
                { "StatId", "920951287"},
                { "Name", "LAST FRIDAY INVEST AS" },
                { "Persons", new List<KeyValuePair<string, Dictionary<string, string>>>{
                        new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                        {
                            {"PersonalId", "1" },
                            {"Role", "Owner"},
                            {"GivenName", "Vas" },
                            {"Surname", "Vas" },
                            {"Sex", "1" }
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                        {
                            {"Role", "Owner"},
                            {"GivenName", "Vasya12345" },
                            {"Surname", "Vasin12345" },
                            {"BirthDate", dateTimeToday.ToString() },
                            {"Sex", "1" }
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                        {
                            {"Role", "Owner"},
                            {"GivenName", "TEST" },
                            {"Surname", "TEST" },
                            {"Sex", "1" }
                        })

                    }
                }
            };
            var resultUnit = new LegalUnit
            {
                UserId = "42",
                Name = "LAST FRIDAY INVEST AS",
                StatId = "920951287",
                PersonsUnits = new List<PersonStatisticalUnit>()
                {
                    new PersonStatisticalUnit()
                    {
                        PersonTypeId = 1,
                        Person = new Person()
                        {
                            PersonalId = "1",
                            Role = 1,
                            GivenName = "Vas",
                            Surname = "Vas",
                            Sex = 1,
                            BirthDate = dateTimeToday,
                            PhoneNumber = "12345"
                        }
                    },
                    new PersonStatisticalUnit()
                    {
                        PersonTypeId = 1,
                        Person = new Person()
                        {
                            Role = 1,
                            GivenName = "Vasya12345",
                            Surname = "Vasin12345",
                            Sex = 1,
                            BirthDate = dateTimeToday
                        }
                    },
                    new PersonStatisticalUnit()
                    {
                        PersonTypeId = 1,
                        Person = new Person()
                        {
                            Role = 1,
                            GivenName = "TEST",
                            Surname = "TEST",
                            Sex = 1,
                        }
                    },

                }
            };
            DatabaseContext.StatisticalUnits.Add(dbunit);
            await DatabaseContext.SaveChangesAsync();
            string userId = "8A071342-863E-4EFB-9B60-04050A6D2F4B";
            Initialize(DatabaseContext, userId);
            IMapper mapper = CreateMapper();
            var userService = new UserService(DatabaseContext, mapper);
            var dataAccess = await userService.GetDataAccessAttributes(userId, StatUnitTypes.LegalUnit);
            var populateService = new PopulateService(
                GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter,
                StatUnitTypes.LegalUnit,
                DatabaseContext,
                userId,
                dataAccess,
                mapper
            );


            var (popUnit, isNeW, errors, historyUnit) = await populateService.PopulateAsync(raw,true, DateTime.Now);

            popUnit.PersonsUnits.Should().BeEquivalentTo(resultUnit.PersonsUnits, op => op.Excluding(x => x.PersonId).Excluding(x => x.PersonId).Excluding(x => x.UnitId).Excluding(x => x.Unit).Excluding(x => x.Person.PersonsUnits).Excluding(x => x.Person.Id));
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

            var populateService = new PopulateService(GetArrayMappingByString(unitMapping), DataSourceAllowedOperation.Alter,StatUnitTypes.LegalUnit, DatabaseContext, Guid.NewGuid().ToString(), new DataAccessPermissions(), CreateMapper());
            var (popUnit, isNeW, errors, historyUnit) = await populateService.PopulateAsync(raw, true, DateTime.Now);

            errors.Should().Be(
                $"StatUnit failed with error: {Resource.StatUnitIdIsNotFound} ({popUnit.StatId})",
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
                UserId = "42",
                StatId = "920951287",
                Name = "LAST FRIDAY INVEST AS"
            });
            await DatabaseContext.SaveChangesAsync();
            var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, StatUnitTypes.LegalUnit, DatabaseContext, Guid.NewGuid().ToString(), new DataAccessPermissions(), CreateMapper());
            var (popUnit, _, error, historyUnit) = await populateService.PopulateAsync(keyValueDict, true, DateTime.Now);

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
                UserId = "8A071342-863E-4EFB-9B60-04050A6D2F4B",
                StatId = "920951287",
                Name = "LAST FRIDAY INVEST AS",
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                {
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            UpdatedBy = "8A071342-863E-4EFB-9B60-04050A6D2F4B",
                            ActivityYear = 2019,
                            Employees = 100,
                            ActivityType = ActivityTypes.Primary,
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
                            UpdatedBy = "8A071342-863E-4EFB-9B60-04050A6D2F4B",
                            ActivityYear = 2020,
                            ActivityType = ActivityTypes.Primary,
                            ActivityCategory = new ActivityCategory()
                            {
                                Code = "68.209"
                            }
                        }
                    }
                }
            };
            string userId = "8A071342-863E-4EFB-9B60-04050A6D2F4B";
            Initialize(DatabaseContext, userId);
            var mapper = CreateMapper();
            var userService = new UserService(DatabaseContext, mapper);
            var dataAccess = await userService.GetDataAccessAttributes(userId, StatUnitTypes.LegalUnit);
            var populateService = new PopulateService(GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter, StatUnitTypes.LegalUnit,
                DatabaseContext, userId, dataAccess, mapper);
            var (popUnit, isNew, errors, historyUnit) = await populateService.PopulateAsync(raw, true, DateTime.Now);
            popUnit.ActivitiesUnits.Should().BeEquivalentTo(unit.ActivitiesUnits,
                op => op.Excluding(z => z.Activity.IdDate).Excluding(z => z.Activity.UpdatedDate));
            popUnit.Should().BeEquivalentTo(unit, op => op.Excluding(z => z.StartPeriod).Excluding(z => z.ActivitiesUnits).Excluding(x => x.RegIdDate).Excluding(x => x.Activities));


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
                            {"ActivityYear", "2021"},
                            {"ActivityCategory.Code", "68.209"},
                        }),
                    }
                }
            };

            Dictionary<string, ActivityCategory> categories = new Dictionary<string, ActivityCategory>();
            categories.Add("67.111", new ActivityCategory()
            {
                Name = "Test",
                Section = "SectionTest",
                Code = "67.111"
            });
            categories.Add("62.020", new ActivityCategory()
            {
                Name = "Test",
                Section = "SectionTest",
                Code = "62.020"
            });
            categories.Add("68.209", new ActivityCategory()
            {
                Name = "Test",
                Section = "SectionTest",
                Code = "68.209"
            });

            DatabaseContext.ActivityCategories.AddRange(categories.Values);
            await DatabaseContext.SaveChangesAsync();

            var dbUnit = new LegalUnit()
            {
                UserId = "42",
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
                            ActivityCategory = categories["67.111"],
                            UpdatedBy = "Test"
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2019,
                            Employees = 2,
                            ActivityCategory = categories["62.020"],
                            UpdatedBy = "Test"
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Secondary,
                            ActivityYear = DateTime.Now.Year - 2,
                            Employees = 1000,
                            ActivityCategory = categories["68.209"],
                            UpdatedBy = "Test"
                        }
                    }
                }
            };
            DatabaseContext.StatisticalUnits.Add(dbUnit);
            await DatabaseContext.SaveChangesAsync();
            var resultUnit = new LegalUnit()
            {
                UserId = "42",
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
                            UpdatedBy = "Test"
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
                            ActivityCategoryId = categories["62.020"].Id,
                            UpdatedBy = "Test"
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
                            ActivityCategoryId = categories[ "68.209"].Id,
                            UpdatedBy = "Test"
                        }
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            ActivityType = ActivityTypes.Primary,
                            ActivityYear = 2021,
                            ActivityCategory = categories[ "68.209"],
                            ActivityCategoryId = categories[ "68.209"].Id,
                            UpdatedBy = "Test"
                        }
                    }
                }
            };
            string userId = "8A071342-863E-4EFB-9B60-04050A6D2F4B";
            Initialize(DatabaseContext, userId);
            var mapper = CreateMapper();
            var userService = new UserService(DatabaseContext, mapper);
            var dataAccess = await userService.GetDataAccessAttributes(userId, StatUnitTypes.LegalUnit);
            var populateService = new PopulateService(GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter,StatUnitTypes.LegalUnit,
                DatabaseContext, userId, dataAccess, mapper);
            var (popUnit, isNew, errors, historyUnit) = await populateService.PopulateAsync(raw, true, DateTime.Now);
            popUnit.ActivitiesUnits.Should().BeEquivalentTo(resultUnit.ActivitiesUnits,
                op => op.Excluding(x => x.Unit).Excluding(x => x.UnitId).Excluding(x => x.ActivityId)
                    .Excluding(x => x.Activity.ActivitiesUnits).Excluding(x => x.Activity.Id).Excluding(x => x.Activity.UpdatedBy)
                    .Excluding(x => x.Activity.ActivityCategoryId).Excluding(x => x.Activity.ActivityCategory.Id)
                    .Excluding(x => x.Activity.IdDate).Excluding(x => x.Activity.UpdatedDate));
        }

        private void Initialize(NSCRegDbContext context, string userId)
        {
            var role = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.Administrator);
            var daa = DataAccessAttributesProvider.Attributes.Select(v => v.Name).ToArray();
            if (role == null)
            {
                role = new Role
                {
                    Name = DefaultRoleNames.Administrator,
                    Status = RoleStatuses.Active,
                    Description = "System administrator role",
                    NormalizedName = DefaultRoleNames.Administrator.ToUpper(),
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[])Enum.GetValues(typeof(SystemFunctions))).Cast<int>(),
                    StandardDataAccessArray = new DataAccessPermissions(daa
                            .Select(x => new Permission(x, true, true)))
                };
                context.Roles.Add(role);
            }

            context.Roles.Add(new Role()
            {
                Name = DefaultRoleNames.Employee,
                Status = RoleStatuses.Active,
                Description = "Employee",
                NormalizedName = DefaultRoleNames.Employee.ToUpper(),
                AccessToSystemFunctionsArray = ((SystemFunctions[])Enum.GetValues(typeof(SystemFunctions))).Cast<int>(),
                StandardDataAccessArray = null
            });
            var anyAdminHere = context.UserRoles.Any(ur => ur.RoleId == role.Id);
            if (anyAdminHere) return;
            var sysAdminUser = context.Users.ToList().FirstOrDefault(u => u.Login == "admin");
            if (sysAdminUser == null)
            {
                sysAdminUser = new User
                {
                    Id = userId,
                    Login = "admin",
                    PasswordHash =
                        "AQAAAAEAACcQAAAAEF+cTdTv1Vbr9+QFQGMo6E6S5aGfoFkBnsrGZ4kK6HIhI+A9bYDLh24nKY8UL3XEmQ==",
                    SecurityStamp = "9479325a-6e63-494a-ae24-b27be29be015",
                    Name = "Admin user",
                    PhoneNumber = "555123456",
                    Email = "admin@email.xyz",
                    NormalizedEmail = "admin@email.xyz".ToUpper(),
                    Status = UserStatuses.Active,
                    Description = "System administrator account",
                    NormalizedUserName = "admin".ToUpper(),
                    DataAccessArray = daa
                };
                context.Users.Add(sysAdminUser);
            }
            var adminUserRoleBinding = new UserRole
            {
                RoleId = role.Id,
                UserId = sysAdminUser.Id
            };
            context.UserRoles.Add(adminUserRoleBinding);
            context.SaveChanges();
        }
    }
}
