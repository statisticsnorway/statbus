using AutoMapper;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Data.Entities.History;
using nscreg.Resources.Languages;
using nscreg.Server.Common;
using nscreg.Server.Common.Models.OrgLinks;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Test.Extensions;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;
using static nscreg.TestUtils.InMemoryDbSqlite;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.Test
{
    public class StatUnitServiceTest
    {
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly ValidationSettings _validationSettings;
        private readonly StatUnitTestHelper _helper;
        private readonly IMapper _mapper;

        public StatUnitServiceTest()
        {
            var builder =
                new ConfigurationBuilder().AddJsonFile(
                    Path.Combine(
                        Directory.GetCurrentDirectory(),
                        "..", "..", "..", "..", "..",
                        "appsettings.Shared.json"),
                    true);
            var configuration = builder.Build();
            _analysisRules = configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();
            _analysisRules.Orphan.CheckOrphanLegalUnits = false;
            _analysisRules.Orphan.CheckLegalUnitRelatedLocalUnits = false;
            _analysisRules.Orphan.CheckEnterpriseGroupRelatedEnterprises = false;
            _mandatoryFields = configuration.GetSection(nameof(DbMandatoryFields)).Get<DbMandatoryFields>();
            _validationSettings = configuration.GetSection(nameof(ValidationSettings)).Get<ValidationSettings>();

            var mapperConfig = new MapperConfiguration(mc =>
            {
                mc.AddProfile(new AutoMapperProfile());
            });

            _mapper = mapperConfig.CreateMapper();
            _helper = new StatUnitTestHelper(_analysisRules, _mandatoryFields, _validationSettings, _mapper);
            var services = new ServiceCollection();
            services.AddAutoMapper(typeof(AutoMapperProfile).Assembly);

            StartupConfiguration.ConfigureAutoMapper(services);
        }

        #region SearchTests

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        private async Task SearchByNameOrAddressTest(StatUnitTypes unitType)
        {
            var unitName = Guid.NewGuid().ToString();
            var addressPart = Guid.NewGuid().ToString();
            var region = new Region { Name = Guid.NewGuid().ToString() };
            var address = new Address { AddressPart1 = addressPart, Region = region };

            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();
                await context.SaveChangesAsync();
                var userId = (await context.Users.FirstOrDefaultAsync(x => x.Login == "admin"))?.Id;

                IStatisticalUnit unit;
                switch (unitType)
                {
                    case StatUnitTypes.LocalUnit:
                        unit = new LocalUnit
                        {
                            Name = unitName,
                            ActualAddress = address,
                            ActualAddressId = address.Id,
                            UserId = userId
                        };
                        await context.LocalUnits.AddAsync((LocalUnit)unit);
                        break;
                    case StatUnitTypes.LegalUnit:
                        unit = new LegalUnit
                        {
                            Name = unitName,
                            ActualAddress = address,
                            ActualAddressId = address.Id,
                            UserId = userId
                        };
                        await context.LegalUnits.AddAsync((LegalUnit)unit);
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        unit = new EnterpriseUnit
                        {
                            Name = unitName,
                            ActualAddress = address,
                            ActualAddressId = address.Id,
                            UserId = userId
                        };
                        await context.EnterpriseUnits.AddAsync((EnterpriseUnit)unit);
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        unit = new EnterpriseGroup
                        {
                            Name = unitName,
                            ActualAddress = address,
                            ActualAddressId = address.Id,
                            UserId = userId
                        };
                        await context.EnterpriseGroups.AddAsync((EnterpriseGroup)unit);
                        break;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(unitType), unitType, null);
                }
                await context.SaveChangesAsync();
                await new ElasticService(context, _mapper).Synchronize(true);
                await Task.Delay(2000);
                var service = new SearchService(null, null, null, null, context, _mapper);

                var query = new SearchQueryM { Name = unitName.Remove(unitName.Length - 1) };
                var result = await service.Search(query, DbContextExtensions.UserId);
                Assert.Equal(1, result.TotalCount);

                query = new SearchQueryM { Address = addressPart.Remove(addressPart.Length - 1) };
                result = await service.Search(query, DbContextExtensions.UserId);
                Assert.Equal(1, result.TotalCount);
            }
        }

        [Fact]
        private async Task SearchByNameMultiplyResultTest()
        {
            var commonName = Guid.NewGuid().ToString();

            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();

                var userId = (await context.Users.FirstOrDefaultAsync(x => x.Login == "admin"))?.Id;

                var legal = new LegalUnit { Name = commonName + Guid.NewGuid(), UserId = userId };
                var local = new LocalUnit { Name = commonName + Guid.NewGuid(), UserId = userId };
                var enterprise = new EnterpriseUnit { Name = commonName + Guid.NewGuid(), UserId = userId };
                var group = new EnterpriseGroup { Name = commonName + Guid.NewGuid(), UserId = userId };

                await context.LegalUnits.AddAsync(legal);
                await context.LocalUnits.AddAsync(local);
                await context.EnterpriseUnits.AddAsync(enterprise);
                await context.EnterpriseGroups.AddAsync(group);
                await context.SaveChangesAsync();
                await new ElasticService(context, _mapper).Synchronize(true);
                await Task.Delay(2000);

                var query = new SearchQueryM { Name = commonName };
                var result = await new SearchService(null, null, null, null, context, _mapper).Search(query, DbContextExtensions.UserId);

                Assert.Equal(4, result.TotalCount);
            }
        }

        [Theory]
        [InlineData("2017", 3, "", 0)]
        [InlineData("2016", 1, "", 0)]
        private async Task SearchUnitsByCode(string code, int rows, string userId, int regId)
        {
            using (var context = CreateDbContext())
            {
                context.Initialize();
                var list = new StatisticalUnit[]
                {
                    new LegalUnit {UserId = "42",StatId = "201701", Name = "Unit1"},
                    new LegalUnit {UserId = "42", StatId = "201602", Name = "Unit2"},
                    new LocalUnit {UserId = "42",StatId = "201702", Name = "Unit3"}
                };
                await context.StatisticalUnits.AddRangeAsync(list);
                var group = new EnterpriseGroup { UserId = "42", StatId = "201703", Name = "Unit4" };
                await context.EnterpriseGroups.AddAsync(group);
                await context.SaveChangesAsync();
                await new ElasticService(context, _mapper).Synchronize(true);
                await Task.Delay(2000);

                var result = await new SearchService(null, null, null, null, context, _mapper)
                    .Search(StatUnitTypes.EnterpriseGroup, code, userId, regId, true);

                Assert.Equal(rows, result.Count());
            }
        }

        [Theory]
        [InlineData(1, 1)]
        [InlineData(2, 2)]
        private async Task SearchUsingSectorCodeIdTest(int sectorCodeId, int rows)
        {
            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();
                var service = new SearchService(null, null, null, null, context, _mapper);

                var userId = (await context.Users.FirstOrDefaultAsync(x => x.Login == "admin"))?.Id;

                var sectorCodes = new[]
                {
                    new SectorCode {Name = "qwe"},
                    new SectorCode {Name = "ewq"},
                };
                await context.SectorCodes.AddRangeAsync(sectorCodes);
                await context.SaveChangesAsync();

                var list = new StatisticalUnit[]
                {
                    new LegalUnit {InstSectorCodeId = sectorCodes[0].Id, Name = "Unit1", UserId = userId},
                    new LegalUnit {InstSectorCodeId = sectorCodes[1].Id, Name = "Unit2", UserId = userId},
                    new EnterpriseUnit {InstSectorCodeId = sectorCodes[1].Id, Name = "Unit4", UserId = userId},
                    new LocalUnit {Name = "Unit3", UserId = userId}
                };
                await context.StatisticalUnits.AddRangeAsync(list);

                var group = new EnterpriseGroup { Name = "Unit5", UserId = userId };
                await context.EnterpriseGroups.AddAsync(group);

                await context.SaveChangesAsync();
                await new ElasticService(context, _mapper).Synchronize(true);
                await Task.Delay(2000);

                var query = new SearchQueryM
                {
                    SectorCodeId = sectorCodeId
                };

                var result = await service.Search(query, DbContextExtensions.UserId);

                Assert.Equal(rows, result.TotalCount);
            }
        }

        [Theory]
        [InlineData(1, 1)]
        [InlineData(2, 0)]
        private async Task SearchUsingLegalFormIdTest(int legalFormId, int rows)
        {
            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();
                var service = new SearchService(null, null, null, null, context, _mapper);

                var userId = (await context.Users.FirstOrDefaultAsync(x => x.Login == "admin"))?.Id;

                var legalForm = new LegalForm { Name = "qwe" };
                await context.LegalForms.AddAsync(legalForm);
                var sectorCode = new SectorCode { Name = "qwe" };
                await context.SectorCodes.AddAsync(sectorCode);
                await context.SaveChangesAsync();

                var list = new StatisticalUnit[]
                {
                    new LegalUnit {LegalFormId = legalForm.Id, Name = "Unit1", UserId = userId},
                    new LegalUnit {Name = "Unit2", UserId = userId},
                    new EnterpriseUnit {InstSectorCodeId = sectorCode.Id, Name = "Unit4", UserId = userId},
                    new LocalUnit {Name = "Unit3", UserId = userId}
                };
                await context.StatisticalUnits.AddRangeAsync(list);

                var group = new EnterpriseGroup { Name = "Unit5", UserId = userId };
                await context.EnterpriseGroups.AddAsync(group);

                context.SaveChanges();
                await new ElasticService(context, _mapper).Synchronize(true);
                await Task.Delay(2000);

                var query = new SearchQueryM
                {
                    LegalFormId = legalFormId
                };

                var result = await service.Search(query, DbContextExtensions.UserId);

                Assert.Equal(rows, result.TotalCount);
            }
        }

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        private async Task SearchUsingUnitTypeTest(StatUnitTypes type)
        {
            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();
                var userId = (await context.Users.FirstOrDefaultAsync(x => x.Login == "admin"))?.Id;
                var unitName = Guid.NewGuid().ToString();
                var legal = new LegalUnit { Name = unitName, UserId = userId };
                var local = new LocalUnit { Name = unitName, UserId = userId };
                var enterprise = new EnterpriseUnit { Name = unitName, UserId = userId };
                var group = new EnterpriseGroup { Name = unitName, UserId = userId };
                await context.LegalUnits.AddAsync(legal);
                await context.LocalUnits.AddAsync(local);
                await context.EnterpriseUnits.AddAsync(enterprise);
                await context.EnterpriseGroups.AddAsync(group);
                await context.SaveChangesAsync();
                await new ElasticService(context, _mapper).Synchronize(true);
                await Task.Delay(2000);

                var query = new SearchQueryM
                {
                    Name = unitName,
                    Type = new List<StatUnitTypes> { type }
                };

                var result = await new SearchService(null, null, null, null, context, _mapper).Search(query, DbContextExtensions.UserId);
                Assert.Equal(1, result.TotalCount);
            }
        }

        #endregion

        #region CreateTest

        [Fact]
        public async Task CreateLegalUnit()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();
                    var activities = await _helper.CreateActivitiesAsync(context);
                    var address = await _helper.CreateAddressAsync(context);
                    await _helper.CreateLegalUnitAsync(context, activities, address, unitName, statId);
                    var lst = context.LegalUnits.ToArray();
                    Assert.IsType<LegalUnit>(context.LegalUnits.Single(x =>
                        x.Name == unitName &&
                        x.ActualAddress.AddressPart1 == address.AddressPart1 &&
                        !x.IsDeleted)
                    );
                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }
        }

        [Fact]
        public async Task CreateLocalUnit()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();

                    var activities = await _helper.CreateActivitiesAsync(context);
                    var address = await _helper.CreateAddressAsync(context);
                    var legalUnit = await _helper.CreateLegalUnitAsync(context, activities, null, unitName, statId);

                    await _helper.CreateLocalUnitAsync(context, activities, address, unitName, legalUnit.RegId);
                    var unit = context.LocalUnits.Local
                        .FirstOrDefault(x =>
                            x.Name == unitName &&
                            x.ActualAddress.AddressPart1 == address.AddressPart1 &&
                            !x.IsDeleted
                        );

                    Assert.IsType<LocalUnit>(unit);

                    await _helper.CreateLocalUnitAsync(context, activities, address, unitName, legalUnit.RegId);
                    Assert.Single(activities);

                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }
        }

        [Fact]
        public async Task CreateEnterpriseUnit()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();
                    var address = await _helper.CreateAddressAsync(context);
                    var activities = await _helper.CreateActivitiesAsync(context);
                    var legalUnit =
                        await _helper.CreateLegalUnitAsync(context, activities, null, Guid.NewGuid().ToString(), statId);
                    var legalUnitIds = new[] { legalUnit.RegId };
                    var enterpriseGroup =
                        await _helper.CreateEnterpriseGroupAsync(context, null, unitName, Array.Empty<int>(), legalUnitIds);

                    await _helper.CreateEnterpriseUnitAsync(context, activities, address, unitName, legalUnitIds,
                        enterpriseGroup?.RegId);

                    Assert.IsType<EnterpriseUnit>(
                        context.EnterpriseUnits.Single(x => x.Name == unitName &&
                                                            x.ActualAddress.AddressPart1 == address.AddressPart1 &&
                                                            !x.IsDeleted));

                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }

        }

        [Fact]
        public async Task CreateEnterpriseGroup()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();

                    var address = await _helper.CreateAddressAsync(context);
                    var activities = await _helper.CreateActivitiesAsync(context);
                    var legalUnit =
                        await _helper.CreateLegalUnitAsync(context, activities, null, Guid.NewGuid().ToString(), statId);
                    var legalUnitIds = new[] { legalUnit.RegId };
                    await _helper.CreateEnterpriseGroupAsync(context, address, unitName, Array.Empty<int>(), legalUnitIds);

                    Assert.IsType<EnterpriseGroup>(
                        context.EnterpriseGroups.Single(x =>
                        x.Name == unitName &&
                        x.ActualAddress.AddressPart1 == address.AddressPart1 &&
                        !x.IsDeleted));

                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }

        }

        #endregion

        #region EditTest

        [Fact]
        public async Task EditDataAccessAttributes()
        {

            using (var context = CreateDbContext())
            {
                context.Initialize();

                var user = context.Users.Include(v => v.UserRoles).Single(v => v.Id == DbContextExtensions.UserId);


                var roleIds = user.UserRoles.Select(v => v.RoleId).ToList();
                var rolesList = context.Roles.Where(v => roleIds.Contains(v.Id)).ToList();

                foreach (var role in rolesList)
                {
                    role.StandardDataAccessArray =
                        new DataAccessPermissions(role.StandardDataAccessArray
                            .Permissions.Where(v => !v.PropertyName.EndsWith(nameof(LegalUnit.ShortName))));
                }

                var userService = new UserService(context, _mapper);

                const string unitName = "Legal with Data Access Limits";
                const string unitShortName = "Default Value";

                var unit = new LegalUnit
                {
                    Name = unitName,
                    UserId = DbContextExtensions.UserId,
                    ShortName = unitShortName
                };
                context.LegalUnits.Add(unit);
                await context.SaveChangesAsync();

                await new EditService(context, _analysisRules, _mandatoryFields, _validationSettings, _mapper).EditLegalUnit(new LegalUnitEditM
                {
                    DataAccess =
                        await userService.GetDataAccessAttributes(DbContextExtensions.UserId, StatUnitTypes.LegalUnit),
                    RegId = unit.RegId,
                    Name = unitName,
                    ShortName = "qwerty 666 / 228 / 322"
                }, DbContextExtensions.UserId);

                await context.SaveChangesAsync();

                var name = context.LegalUnits.Where(v => v.Name == unitName)
                    .Select(v => v.ShortName).Single();
                Assert.Equal(unitShortName, name);
            }


        }

        [Fact]
        public async Task EditActivities()
        {
            const string unitName = "Legal with activities";
            var activity1 = new Activity
            {
                ActivityYear = 2017,
                Employees = 666,
                Turnover = 1000000,
                ActivityCategory = new ActivityCategory { Code = "01.12.0", Name = "����������� ����", Section = "A" },
                ActivityType = ActivityTypes.Primary,
                UpdatedBy = "Test"
            };

            var activity2 = new Activity
            {
                ActivityYear = 2017,
                Employees = 888,
                Turnover = 2000000,
                ActivityCategory = new ActivityCategory
                {
                    Code = "01.13",
                    Name = "����������� ������, ����, �����- � ������������",
                    Section = "A"
                },
                ActivityType = ActivityTypes.Secondary,
                UpdatedBy = "Test"
            };

            var activity3 = new Activity
            {
                ActivityYear = 2017,
                Employees = 999,
                Turnover = 3000000,
                ActivityCategory = new ActivityCategory
                {
                    Code = "01.13.1",
                    Name = "����������� �������� ������ � �� �����",
                    Section = "A"
                },
                ActivityType = ActivityTypes.Ancilliary,
                UpdatedBy = "Test"
            };


            var activityCategory = new ActivityCategory
            {
                Code = "02.3",
                Name = "���� ������������ ����������� �������������",
                Section = "A"
            };

            using (var context = CreateDbContext())
            {
                context.Initialize();

                context.ActivityCategories.Add(activityCategory);
                context.LegalUnits.AddRange(new List<LegalUnit>
                {
                    new LegalUnit
                    {
                        Name = unitName,
                        UserId = DbContextExtensions.UserId,
                        ActivitiesUnits = new List<ActivityStatisticalUnit>
                        {
                            new ActivityStatisticalUnit
                            {
                                Activity = activity1
                            },
                            new ActivityStatisticalUnit
                            {
                                Activity = activity2
                            },
                            new ActivityStatisticalUnit
                            {
                                Activity = activity3
                            }
                        }
                    }
                });
                context.SaveChanges();

                var unitId = context.LegalUnits.First(x => x.Name == unitName).RegId;
                const int changedEmployees = 9999;
                var legalEditResult = await new EditService(context, _analysisRules, _mandatoryFields, _validationSettings, _mapper).EditLegalUnit(
                    new LegalUnitEditM
                    {
                        RegId = unitId,
                        Name = "new name test",
                        DataAccess = DbContextExtensions.DataAccessLegalUnit,
                        Activities = new List<ActivityM>
                        {
                            new ActivityM //New
                            {
                                ActivityCategoryId = 1,
                                ActivityType = ActivityTypes.Primary,
                                Employees = 2,
                                Turnover = 10,
                                ActivityYear = 2016,
                                IdDate = new DateTimeOffset(2017, 03, 28, 0, 0, 0, new TimeSpan())
                            },
                            new ActivityM //Not Changed
                            {
                                Id = activity1.Id,
                                ActivityCategoryId = 1,
                                ActivityType = activity1.ActivityType,
                                IdDate = activity1.IdDate,
                                Employees = activity1.Employees,
                                Turnover = activity1.Turnover,
                                ActivityYear = activity1.ActivityYear
                            },
                            new ActivityM //Changed
                            {
                                Id = activity2.Id,
                                ActivityCategoryId = 2,
                                ActivityType = activity2.ActivityType,
                                IdDate = activity2.IdDate,
                                Employees = changedEmployees,
                                Turnover = activity2.Turnover,
                                ActivityYear = activity2.ActivityYear
                            }
                        }
                    }, DbContextExtensions.UserId);
                if (legalEditResult != null && legalEditResult.Any()) return;

                var unitResult = context.LegalUnits
                    .Include(v => v.ActivitiesUnits)
                    .ThenInclude(v => v.Activity)
                    .Single(v => v.RegId == unitId).Activities;

                var activities = unitResult as Activity[] ?? unitResult.ToArray();
                Assert.Equal(3, activities.Length);
                Assert.DoesNotContain(activities, v => v.Id == activity3.Id);
                Assert.Contains(activities, v => v.Id == activity1.Id);
                Assert.Contains(activities, v => v.Employees == changedEmployees);
                Assert.NotEqual(activity2.Id, activities.First(v => v.Employees == changedEmployees).Id);
            }
        }

        [Fact]
        public async Task EditLegalUnit()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var unitNameEdit = Guid.NewGuid().ToString();
                var duplicateName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();

                    var activities = await _helper.CreateActivitiesAsync(context);
                    await _helper.CreateLegalUnitAsync(context, activities, null, unitName, statId);
                    await _helper.CreateLegalUnitAsync(context, activities, null, duplicateName, statId);

                    var unitId = context.LegalUnits.First(x => x.Name == unitName).RegId;

                    await _helper.EditLegalUnitAsync(context, activities, unitId, unitNameEdit);

                    Assert.IsType<LegalUnit>(
                        context.LegalUnits.First(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    Assert.IsType<LegalUnitHistory>(
                        context.LegalUnitHistory.First(x => x.ParentId == unitId && x.Name == unitName));

                    Type actual = null;
                    try
                    {
                        await _helper.EditLegalUnitAsync(context, activities, unitId, duplicateName);
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                        Assert.Equal(typeof(BadRequestException), actual);
                    }

                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }
        }

        [Fact]
        private async Task EditLocalUnit()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var unitNameEdit = Guid.NewGuid().ToString();
                var dublicateName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();
                    var activities = await _helper.CreateActivitiesAsync(context);
                    var legalUnit =
                        await _helper.CreateLegalUnitAsync(context, activities, null, Guid.NewGuid().ToString(), statId);

                    await _helper.CreateLocalUnitAsync(context, activities, null, unitName, legalUnit.RegId);
                    await _helper.CreateLocalUnitAsync(context, activities, null, dublicateName, legalUnit.RegId);

                    var unitId = context.LocalUnits.First(x => x.Name == unitName).RegId;

                    await _helper.EditLocalUnitAsync(context, activities, unitId, unitNameEdit, legalUnit.RegId);

                    Assert.IsType<LocalUnit>(
                        context.LocalUnits.First(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    Assert.IsType<LocalUnitHistory>(
                        context.LocalUnitHistory.First(x => x.ParentId == unitId && x.Name == unitName));

                    Type actual = null;
                    try
                    {
                        await _helper.EditLocalUnitAsync(context, activities, unitId, dublicateName, legalUnit.RegId);
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                        Assert.Equal(typeof(BadRequestException), actual);
                    }
                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }

        }

        [Fact]
        private async Task EditEnterpriseUnit()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var unitNameEdit = Guid.NewGuid().ToString();
                var duplicateName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();

                    var activities = await _helper.CreateActivitiesAsync(context);
                    var legalUnit =
                        await _helper.CreateLegalUnitAsync(context, activities, null, Guid.NewGuid().ToString(), statId);
                    var legalUnitIds = new[] { legalUnit.RegId };
                    var enterpriseGroup = await _helper.CreateEnterpriseGroupAsync(context, null, Guid.NewGuid().ToString(),
                        context.EnterpriseUnits.Select(eu => eu.RegId).ToArray(), legalUnitIds);

                    await _helper.CreateEnterpriseUnitAsync(context, activities, null, unitName, legalUnitIds,
                        enterpriseGroup?.RegId);
                    await _helper.CreateEnterpriseUnitAsync(context, activities, null, duplicateName, legalUnitIds,
                        enterpriseGroup?.RegId);

                    var editUnitId = context.EnterpriseUnits.Single(x => x.Name == unitName).RegId;

                    await _helper.EditEnterpriseUnitAsync(context, activities, legalUnitIds, editUnitId, unitNameEdit,
                        enterpriseGroup?.RegId);

                    Assert.IsType<EnterpriseUnit>(
                        context.EnterpriseUnits.Single(
                            x => x.RegId == editUnitId && x.Name == unitNameEdit && !x.IsDeleted));
                    Assert.IsType<EnterpriseUnitHistory>(
                        context.EnterpriseUnitHistory.Single(
                            x => x.ParentId == editUnitId && x.Name == unitName));
                    var entLegalsUnits = context.EnterpriseUnits.First(x => x.Name == unitNameEdit).LegalUnits;

                    Assert.Equal(1,
                        entLegalsUnits.Count);

                    Type actual = null;
                    try
                    {
                        await _helper.EditEnterpriseUnitAsync(context, activities, legalUnitIds, editUnitId, duplicateName,
                            enterpriseGroup?.RegId);
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                        Assert.Equal(typeof(BadRequestException), actual);
                    }

                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }

        }

        [Fact]
        public async Task EditEnterpriseGroup()
        {
            try
            {
                var unitName = Guid.NewGuid().ToString();
                var unitNameEdit = Guid.NewGuid().ToString();
                var duplicateName = Guid.NewGuid().ToString();
                var statId = Guid.NewGuid().ToString();

                using (var context = CreateDbContext())
                {
                    context.Initialize();

                    var activities = await _helper.CreateActivitiesAsync(context);
                    var legalUnit =
                        await _helper.CreateLegalUnitAsync(context, activities, null, Guid.NewGuid().ToString(), statId);
                    var legalUnitsIds = new[] { legalUnit.RegId };
                    var enterpriseGroup = await _helper.CreateEnterpriseGroupAsync(context, null, Guid.NewGuid().ToString(),
                        context.EnterpriseUnits.Select(eu => eu.RegId).ToArray(), legalUnitsIds);

                    await _helper.CreateEnterpriseUnitAsync(context, activities, null, unitName, legalUnitsIds,
                        enterpriseGroup?.RegId);
                    await _helper.CreateEnterpriseUnitAsync(context, activities, null, duplicateName, legalUnitsIds,
                        enterpriseGroup?.RegId);

                    var enterpriseUnitsIds = context.EnterpriseUnits.Select(eu => eu.RegId).ToArray();

                    await _helper.CreateEnterpriseGroupAsync(context, null, unitName, enterpriseUnitsIds, legalUnitsIds);
                    await _helper.CreateEnterpriseGroupAsync(context, null, duplicateName, enterpriseUnitsIds,
                        legalUnitsIds);

                    var unitId = context.EnterpriseGroups.First(x => x.Name == unitName).RegId;

                    await _helper.EditEnterpriseGroupAsync(context, unitId, unitNameEdit, enterpriseUnitsIds,
                        legalUnitsIds);

                    Assert.IsType<EnterpriseGroup>(
                        context.EnterpriseGroups.FirstOrDefault(
                            x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    Assert.IsType<EnterpriseGroupHistory>(
                        context.EnterpriseGroupHistory.FirstOrDefault(
                            x => x.ParentId == unitId && x.Name == unitName));

                    Type actual = null;
                    try
                    {
                        await _helper.EditEnterpriseGroupAsync(context, unitId, duplicateName, enterpriseUnitsIds,
                            legalUnitsIds);
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                        Assert.Equal(typeof(BadRequestException), actual);
                    }

                }
            }
            catch (Exception e)
            {
                Assert.True(e.Message == nameof(Resource.ElasticSearchIsDisable));
            }

        }

        #endregion

        #region DeleteTest

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        private async Task DeleteTest(StatUnitTypes type)
        {
            var unitName = Guid.NewGuid().ToString();
            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();
                int unitId;
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        await context.LegalUnits.AddAsync(new LegalUnit
                        {
                            Name = unitName,
                            IsDeleted = false,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.LegalUnits.SingleAsync(x => x.Name == unitName && !x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, true, DbContextExtensions.UserId);
                        Assert.IsType<LegalUnit>(await context.LegalUnits.SingleAsync(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<LegalUnitHistory>(await context.LegalUnitHistory.SingleAsync(x => x.Name == unitName && !x.IsDeleted && x.ParentId == unitId));
                        break;
                    case StatUnitTypes.LocalUnit:
                        await context.LocalUnits.AddAsync(new LocalUnit
                        {
                            Name = unitName,
                            IsDeleted = false,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.LocalUnits.SingleAsync(x => x.Name == unitName && !x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, true, DbContextExtensions.UserId);
                        Assert.IsType<LocalUnit>(await context.LocalUnits.SingleAsync(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<LocalUnitHistory>(await context.LocalUnitHistory.SingleAsync(x => x.Name == unitName && !x.IsDeleted && x.ParentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        await context.EnterpriseUnits.AddAsync(new EnterpriseUnit
                        {
                            Name = unitName,
                            IsDeleted = false,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.EnterpriseUnits.SingleAsync(x => x.Name == unitName && !x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, true, DbContextExtensions.UserId);
                        Assert.IsType<EnterpriseUnit>(await context.EnterpriseUnits.SingleAsync(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<EnterpriseUnitHistory>(
                            await context.EnterpriseUnitHistory.SingleAsync(
                                x => x.Name == unitName && !x.IsDeleted && x.ParentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        await context.EnterpriseGroups.AddAsync(new EnterpriseGroup
                        {
                            Name = unitName,
                            IsDeleted = false,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.EnterpriseGroups.SingleAsync(x => x.Name == unitName && !x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, true, DbContextExtensions.UserId);
                        Assert.IsType<EnterpriseGroup>(
                            await context.EnterpriseGroups.SingleAsync(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<EnterpriseGroupHistory>(
                            await context.EnterpriseGroupHistory.SingleAsync(
                                x => x.Name == unitName && !x.IsDeleted && x.ParentId == unitId));
                        break;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(type), type, null);
                }
            }
        }

        #endregion

        #region UndeleteTest

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        private async Task UndeleteTest(StatUnitTypes type)
        {

            var unitName = Guid.NewGuid().ToString();
            using (var context = CreateSqliteDbContext())
            {
                context.Initialize();
                int unitId;
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        await context.LegalUnits.AddAsync(new LegalUnit
                        {
                            Name = unitName,
                            IsDeleted = true,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.LegalUnits.SingleAsync(x => x.Name == unitName && x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, false, DbContextExtensions.UserId);
                        Assert.IsType<LegalUnit>(await context.LegalUnits.SingleAsync(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<LegalUnitHistory>(
                            await context.LegalUnitHistory.SingleAsync(x => x.Name == unitName && x.IsDeleted && x.ParentId == unitId));
                        break;
                    case StatUnitTypes.LocalUnit:
                        await context.LocalUnits.AddAsync(new LocalUnit
                        {
                            Name = unitName,
                            IsDeleted = true,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.LocalUnits.SingleAsync(x => x.Name == unitName && x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, false, DbContextExtensions.UserId);
                        Assert.IsType<LocalUnit>(await context.LocalUnits.SingleAsync(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<LocalUnitHistory>(
                            await context.LocalUnitHistory.SingleAsync(x => x.Name == unitName && x.IsDeleted && x.ParentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        await context.EnterpriseUnits.AddAsync(new EnterpriseUnit
                        {
                            Name = unitName,
                            IsDeleted = true,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.EnterpriseUnits.SingleAsync(x => x.Name == unitName && x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, false, DbContextExtensions.UserId);
                        Assert.IsType<EnterpriseUnit>(
                            await context.EnterpriseUnits.SingleAsync(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<EnterpriseUnitHistory>(
                            await context.EnterpriseUnitHistory.SingleAsync(
                                x => x.Name == unitName && x.IsDeleted && x.ParentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        await context.EnterpriseGroups.AddAsync(new EnterpriseGroup
                        {
                            Name = unitName,
                            IsDeleted = true,
                            UserId = DbContextExtensions.UserId
                        });
                        await context.SaveChangesAsync();
                        await new ElasticService(context, _mapper).Synchronize(true);
                        await Task.Delay(2000);
                        unitId = (await context.EnterpriseGroups.SingleAsync(x => x.Name == unitName && x.IsDeleted)).RegId;
                        new DeleteService(context, _mapper).DeleteUndelete(type, unitId, false, DbContextExtensions.UserId);
                        Assert.IsType<EnterpriseGroup>(
                            await context.EnterpriseGroups.SingleAsync(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<EnterpriseGroupHistory>(
                            await context.EnterpriseGroupHistory.SingleAsync(
                                x => x.Name == unitName && x.IsDeleted && x.ParentId == unitId));
                        break;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(type), type, null);
                }
            }
        }

        #endregion

        #region View OrgLinks

        [Fact]
        private async Task GetOrgLinksWithParent()
        {
            var expectedRoot = new LegalUnit { UserId = "42", Name = "le0" };
            var childNode = new LocalUnit { UserId = "42", Name = "lo1" };
            OrgLinksNode actualRoot;
            using (var ctx = CreateDbContext())
            {
                ctx.LegalUnits.Add(expectedRoot);
                await ctx.SaveChangesAsync();
                childNode.ParentOrgLink = expectedRoot.RegId;
                ctx.LocalUnits.Add(childNode);
                await ctx.SaveChangesAsync();

                actualRoot = await new ViewService(ctx, null, null, null, _mandatoryFields, null, _mapper)
                    .GetOrgLinksTree(childNode.RegId);
            }

            Assert.NotNull(actualRoot);
            Assert.NotNull(actualRoot.OrgLinksNodes);
            Assert.NotEmpty(actualRoot.OrgLinksNodes);
            Assert.Equal(childNode.RegId, actualRoot.OrgLinksNodes.First().RegId);
            Assert.Empty(actualRoot.OrgLinksNodes.First().OrgLinksNodes);
        }

        [Fact]
        private async Task GetOrgLinksWithChildNodes()
        {
            var expectedRoot = new LegalUnit { UserId = "42", Name = "42", ParentOrgLink = null };
            OrgLinksNode actualRoot;
            using (var ctx = CreateDbContext())
            {
                ctx.LegalUnits.Add(expectedRoot);
                await ctx.SaveChangesAsync();
                ctx.LocalUnits.AddRange(
                    new LocalUnit { UserId = "42", Name = "17", ParentOrgLink = expectedRoot.RegId },
                    new LocalUnit { UserId = "42", Name = "3.14", ParentOrgLink = expectedRoot.RegId });
                await ctx.SaveChangesAsync();

                actualRoot = await new ViewService(ctx, null, null, null, _mandatoryFields, null, _mapper)
                    .GetOrgLinksTree(expectedRoot.RegId);
            }

            Assert.NotNull(actualRoot);
            Assert.True(expectedRoot.RegId > 0);
            Assert.Equal(expectedRoot.RegId, actualRoot.RegId);
            Assert.Null(actualRoot.ParentOrgLink);
            Assert.False(string.IsNullOrEmpty(expectedRoot.Name));
            Assert.Equal(expectedRoot.Name, actualRoot.Name);
            Assert.NotNull(actualRoot.OrgLinksNodes);
            Assert.NotEmpty(actualRoot.OrgLinksNodes);
            Assert.Equal(2, actualRoot.OrgLinksNodes.Count());
            Assert.Contains(actualRoot.OrgLinksNodes, x => x.Name == "17");
            Assert.Contains(actualRoot.OrgLinksNodes, x => x.Name == "3.14");
        }

        [Fact]
        private async Task GetOrgLinksWithNoChildNodes()
        {
            var expectedRoot = new LegalUnit { UserId = "42", Name = "42", ParentOrgLink = null };
            OrgLinksNode actualRoot;
            using (var ctx = CreateDbContext())
            {
                ctx.LegalUnits.Add(expectedRoot);
                await ctx.SaveChangesAsync();

                actualRoot = await new ViewService(ctx, null, null, null, _mandatoryFields, null, _mapper)
                    .GetOrgLinksTree(expectedRoot.RegId);
            }

            Assert.NotNull(actualRoot);
            Assert.True(expectedRoot.RegId > 0);
            Assert.Equal(expectedRoot.RegId, actualRoot.RegId);
            Assert.Null(actualRoot.ParentOrgLink);
            Assert.False(string.IsNullOrEmpty(expectedRoot.Name));
            Assert.Equal(expectedRoot.Name, actualRoot.Name);
            Assert.NotNull(actualRoot.OrgLinksNodes);
            Assert.Empty(actualRoot.OrgLinksNodes);
        }

        #endregion
    }
}
