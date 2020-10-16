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
using nscreg.Server.Common;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services;
using Xunit;
using Xunit.Abstractions;
using Activity = nscreg.Data.Entities.Activity;

namespace nscreg.Business.Test.DataSources
{
    public class PopulateServiceTest : BaseTest
    {
        public static object locker = new object(); 
        public PopulateServiceTest(ITestOutputHelper helper) : base(helper)
        {
            lock (locker)
            {
                Mapper.Reset();
                Mapper.Initialize(cfg =>
                {
                    cfg.AddProfile<AutoMapperProfile>();
                });

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
            var mappings =
    "statId-StatId,name-Name,PersonRole-Persons.Person.Role,PersonGivenName-Persons.Person.GivenName,PersonSurname-Persons.Person.Surname,PersonSex-Persons.Person.Sex";

            var personTypes = new List<PersonType>(){new PersonType() { Name = "DIRECTOR", Id = 0 }, new PersonType(){ Name = "Owner", Id = 0 }, new PersonType{Name ="TEST",Id = 0} };
            DatabaseContext.PersonTypes.AddRange(personTypes);
            await DatabaseContext.SaveChangesAsync();
            await DatabaseContext.PersonTypes.LoadAsync();
            var dbunit = new LegalUnit
            {
                Name = "LAST FRIDAY INVEST AS",
                StatId = "920951287",
                PersonsUnits = new List<PersonStatisticalUnit>()
                    {
                        new PersonStatisticalUnit()
                        {
                            PersonTypeId = personTypes[0].Id,
                            Person = new Person()
                            {
                                GivenName = "Vasya",
                                Surname = "Vasin",
                                Sex = 1,
                                Role = personTypes[0].Id,
                            }
                        },
                        new PersonStatisticalUnit()
                        {
                            PersonTypeId = personTypes[2].Id,
                            Person = new Person()
                            {
                                GivenName = "Vasya12345",
                                Surname = "Vasin12345",
                                Sex = 1,
                                Role = personTypes[2].Id,
                            }
                        },
                    }
            };
            var resultUnit = new LegalUnit
            {
                Name = "LAST FRIDAY INVEST AS",
                StatId = "920951287",
                PersonsUnits = new List<PersonStatisticalUnit>()
                {
                    new PersonStatisticalUnit()
                    {
                        PersonTypeId = personTypes[0].Id,
                        Person = new Person()
                        {
                            Id = 2,
                            GivenName = "Vasya",
                            Surname = "Vasin",
                            Sex = 1,
                            Role = personTypes[0].Id,
                        }
                    },
                    new PersonStatisticalUnit()
                    {
                        PersonTypeId = personTypes[2].Id,
                        Person = new Person()
                        {
                            Id = 4,
                            GivenName = "Vasya12345",
                            Surname = "Vasin12345",
                            Sex = 1,
                            Role = personTypes[2].Id,
                        }
                    },
                    new PersonStatisticalUnit()
                    {
                        PersonTypeId = personTypes[1].Id,
                        Person = new Person()
                        {
                            GivenName = "Vas",
                            Surname = "Vas",
                            Sex = 1,
                            Role = personTypes[1].Id,
                        }
                    },
                    
                }
            };
            DatabaseContext.StatisticalUnits.Add(dbunit);
            await DatabaseContext.SaveChangesAsync();
            string userId = "8A071342-863E-4EFB-9B60-04050A6D2F4B";
            Initialize(DatabaseContext, userId);
            var userService = new UserService(DatabaseContext);
            var dataAccess = await userService.GetDataAccessAttributes(userId, StatUnitTypes.LegalUnit);
            var populateService = new PopulateService(GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter, StatUnitTypes.LegalUnit,
                DatabaseContext, userId, dataAccess);

            var raw = new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                    { "Persons", new List<KeyValuePair<string, Dictionary<string, string>>>{
                            new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                        {
                            {"Role", "Owner"},
                            {"GivenName", "Vas" },
                            {"Surname", "Vas" },
                            {"Sex", "1" }
                        })

                        }
                    }
                };
            var (popUnit, isNeW, errors, historyUnit) = await populateService.PopulateAsync(raw, true);

            popUnit.PersonsUnits.Should().BeEquivalentTo(resultUnit.PersonsUnits, op => op.Excluding(x => x.PersonId).Excluding(x => x.PersonId).Excluding(x => x.UnitId).Excluding(x => x.Unit).Excluding(x => x.Person.PersonsUnits));
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

            var populateService = new PopulateService(GetArrayMappingByString(unitMapping), DataSourceAllowedOperation.Alter,StatUnitTypes.LegalUnit, DatabaseContext, Guid.NewGuid().ToString(), new DataAccessPermissions());
            var (popUnit, isNeW, errors, historyUnit) = await populateService.PopulateAsync(raw, true);

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
            var populateService = new PopulateService(GetArrayMappingByString(mappings), DataSourceAllowedOperation.Create, StatUnitTypes.LegalUnit, DatabaseContext, Guid.NewGuid().ToString(), new DataAccessPermissions());
            var (popUnit, _, error, historyUnit) = await populateService.PopulateAsync(keyValueDict, true);

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
                            ActivityYear = DateTime.Now.Year - 1,
                            ActivityType = ActivityTypes.Secondary,
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
            var userService = new UserService(DatabaseContext);
            var dataAccess = await userService.GetDataAccessAttributes(userId, StatUnitTypes.LegalUnit);
            var populateService = new PopulateService(GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter, StatUnitTypes.LegalUnit,
                DatabaseContext, userId, dataAccess);
            var (popUnit, isNew, errors, historyUnit) = await populateService.PopulateAsync(raw, true);

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
            string userId = "8A071342-863E-4EFB-9B60-04050A6D2F4B";
            Initialize(DatabaseContext, userId);
           
            var userService = new UserService(DatabaseContext);
            var dataAccess = await userService.GetDataAccessAttributes(userId, StatUnitTypes.LegalUnit);
            var populateService = new PopulateService(GetArrayMappingByString(mappings),
                DataSourceAllowedOperation.CreateAndAlter,StatUnitTypes.LegalUnit,
                DatabaseContext, userId, dataAccess);
            var (popUnit, isNew, errors, historyUnit) = await populateService.PopulateAsync(raw, true);
            popUnit.ActivitiesUnits.Should().BeEquivalentTo(resultUnit.ActivitiesUnits,
                op => op.Excluding(x => x.Unit).Excluding(x => x.UnitId).Excluding(x => x.ActivityId)
                    .Excluding(x => x.Activity.ActivitiesUnits).Excluding(x => x.Activity.Id).Excluding(x => x.Activity.UpdatedBy));
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
            var sysAdminUser = context.Users.FirstOrDefault(u => u.Login == "admin");
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
