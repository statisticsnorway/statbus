using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.SampleFrames;
using nscreg.Server.Core;
using nscreg.Server.Test.Extensions;
using nscreg.TestUtils;
using nscreg.Utilities.Enums.Predicate;
using Newtonsoft.Json;
using Xunit;

namespace nscreg.Server.Test
{
    public class SampleFramesServiceTest
    {
        public SampleFramesServiceTest()
        {
            //StartupConfiguration.ConfigureAutoMapper();
        }

        [Fact]
        private async Task Create()
        {
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.Initialize();

                await CreateStatisticalUnitsAsync(context);

                await new SampleFramesService(context, null).Create(
                    new SampleFrameM
                    {
                        Name = "Sample frame name",
                        Predicate = CreateExpressionGroup(),
                        Fields = new[] {FieldEnum.Address}
                    },
                    (await context.Users.FirstAsync()).Id);

                Assert.Equal(1, await context.SampleFrames.CountAsync());
            }
        }

        [Fact]
        private async Task Edit()
        {
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.Initialize();

                await CreateStatisticalUnitsAsync(context);
                var expressionTree = CreateExpressionGroup();

                var service = new SampleFramesService(context, null);
                await service.Create(
                    new SampleFrameM
                    {
                        Name = "Sample frame name",
                        Predicate = expressionTree,
                        Fields = new[] {FieldEnum.Address}
                    },
                    (await context.Users.FirstAsync()).Id);

                Assert.Equal(1, await context.SampleFrames.CountAsync());

                await service.Edit(
                    (await context.SampleFrames.FirstOrDefaultAsync()).Id,
                    new SampleFrameM
                    {
                        Id = (await context.SampleFrames.FirstOrDefaultAsync()).Id,
                        Predicate = expressionTree,
                        Name = "New sample frame name",
                        Fields = new[] {FieldEnum.Address}
                    },
                    (await context.Users.FirstAsync()).Id);

                Assert.Equal(1, await context.SampleFrames.CountAsync());
                Assert.Equal("New sample frame name", (await context.SampleFrames.FirstOrDefaultAsync()).Name);
            }
        }

        [Fact]
        private async void Delete()
        {
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.Initialize();

                var service = new SampleFramesService(context, null);
                var userId = (await context.Users.FirstAsync()).Id;
                await service.Create(
                    new SampleFrameM
                    {
                        Predicate = CreateExpressionGroup(),
                        Name = "Sample frame name",
                        Fields = new[] {FieldEnum.Address}
                    }, userId
                    );

                Assert.Equal(1, await context.SampleFrames.CountAsync());

                await service.Delete((await context.SampleFrames.FirstOrDefaultAsync()).Id, userId);
                Assert.Equal(0, await context.SampleFrames.CountAsync());
            }
        }

        [Fact]
        private async void Preview()
        {
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.Initialize();

                await CreateStatisticalUnitsAsync(context);
                var service = new SampleFramesService(context, null);

                await service.Create(
                    new SampleFrameM
                    {
                        Name = "Sample frame name",
                        Predicate = CreateExpressionGroup(),
                        Fields = new[] { FieldEnum.RegId, FieldEnum.Name }
                    },
                    (await context.Users.FirstAsync()).Id);

                Assert.Equal(1, await context.SampleFrames.CountAsync());

                var existing = await context.SampleFrames.FirstOrDefaultAsync();

                var units = await context.StatisticalUnits.ToListAsync();
                var expected = new[]
                {
                    new {RegId = units[0].RegId.ToString(), units[0].Name},
                    new {RegId = units[1].RegId.ToString(), units[1].Name}
                };
                var actual = (await service.Preview(existing.Id,(await context.Users.FirstAsync()).Id, 2)).ToArray();

                Assert.Equal(expected.Length, actual.Length);
                Assert.Equal(expected[0].RegId, actual[0][FieldEnum.RegId]);
                Assert.Equal(expected[1].Name, actual[1][FieldEnum.Name]);
            }
        }

        [Fact]
        private async void GetAll()
        {
            SearchVm<SampleFrameM> actual;
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.Initialize();
                var userId = (await context.Users.FirstOrDefaultAsync()).Id;
                context.SampleFrames.AddRange(
                    new SampleFrame
                    {
                        Fields = JsonConvert.SerializeObject(new[] {FieldEnum.Name, FieldEnum.ShortName}),
                        Name = "1",
                        UserId = userId,
                        Predicate = JsonConvert.SerializeObject(CreateExpressionGroup()),
                    },
                    new SampleFrame
                    {
                        Fields = JsonConvert.SerializeObject(new[]
                            {FieldEnum.StatId, FieldEnum.Name, FieldEnum.ShortName}),
                        Name = "2",
                        UserId = userId,
                        Predicate = JsonConvert.SerializeObject(CreateExpressionGroup()),
                    });
                await context.SaveChangesAsync();

                actual = await new SampleFramesService(context, null).GetAll(new SearchQueryM {Page = 1, PageSize = 1}, (await context.Users.FirstAsync()).Id);
            }

            Assert.Single(actual.Result);
            Assert.Equal(2, actual.TotalCount);
        }

        [Fact]
        private async void GetById()
        {
            SampleFrameM actual;
            var expectedFields = new[] {FieldEnum.StatId, FieldEnum.Name};
            var expectedPredicate = CreateExpressionGroup();
            var expected = new SampleFrame
            {
                Fields = JsonConvert.SerializeObject(expectedFields),
                Name = "test",
                Description = "SF test",
                Predicate = JsonConvert.SerializeObject(expectedPredicate),
                User = new User {UserName = "test user"}
            };
            using (var context = InMemoryDb.CreateDbContext())
            {
                context.SampleFrames.Add(expected);
                await context.SaveChangesAsync();

                actual = await new SampleFramesService(context, null).GetById(expected.Id, (await context.Users.FirstOrDefaultAsync()).Id);
            }

            Assert.Equal(expected.Name, actual.Name);
            Assert.Equal(expected.Description, actual.Description);
            Assert.Equal(expectedFields[0], actual.Fields.First());
            Assert.Equal(expectedFields[1], actual.Fields.Last());
            Assert.Equal(expectedPredicate.Groups.Count(), actual.Predicate.Groups.Count());
        }

        private static ExpressionGroup CreateExpressionGroup()
        {
            return new ExpressionGroup
            {
                Groups = new[]
                {
                    new ExpressionTuple<ExpressionGroup>()
                    {
                        Predicate = new ExpressionGroup()
                        {
                            Groups = new []
                            {
                                new ExpressionTuple<ExpressionGroup>()
                                {
                                    Predicate = new ExpressionGroup()
                                    {
                                        Rules = new []
                                        {
                                            new ExpressionTuple<Rule>()
                                            {
                                                Predicate = new Rule()
                                                {
                                                    Field = FieldEnum.Turnover,
                                                    Value = 22,
                                                    Operation = OperationEnum.Equal
                                                }
                                            },
                                            new ExpressionTuple<Rule>()
                                            {
                                                Comparison = ComparisonEnum.Or,
                                                Predicate = new Rule()
                                                {
                                                    Field = FieldEnum.EmployeesYear,
                                                    Value = 2016,
                                                    Operation = OperationEnum.GreaterThanOrEqual
                                                }
                                            }, 
                                        }
                                    }
                                },
                                new ExpressionTuple<ExpressionGroup>
                                {
                                    Comparison = ComparisonEnum.And,
                                    Predicate = new ExpressionGroup
                                    {
                                        Rules = new[]
                                        {
                                            new ExpressionTuple<Rule>
                                            {
                                                Predicate = new Rule
                                                {
                                                    Field = FieldEnum.TurnoverYear,
                                                    Value  = 2011,
                                                    Operation = OperationEnum.LessThanOrEqual
                                                }
                                            }
                                        }
                                    }
                                } 
                            }
                        }
                    },
                    new ExpressionTuple<ExpressionGroup>
                    {
                        Comparison = ComparisonEnum.And,
                        Predicate = new ExpressionGroup()
                        {
                            Rules = new []
                            {
                                new ExpressionTuple<Rule>()
                                {
                                    Predicate = new Rule()
                                    {
                                        Field = FieldEnum.Turnover,
                                        Value = 210,
                                        Operation = OperationEnum.LessThanOrEqual
                                    }
                                }, 
                            }
                        }
                    }
                }
            };
        }


        private static async Task CreateStatisticalUnitsAsync(NSCRegDbContext context)
        {
            await CreateLegalUnitAsync(context, new LegalUnit
            {
                UserId = "42",
                Name = Guid.NewGuid().ToString(),
                FreeEconZone = true,
                EmployeesYear = 2016,
                Employees = 20,
                TurnoverYear = 2010,
                Turnover = 200,
                ActualAddress = await CreateAddressAsync(context, "41701")
            });

            await CreateLegalUnitAsync(context, new LegalUnit
            {
                UserId = "42",
                Name = Guid.NewGuid().ToString(),
                FreeEconZone = true,
                EmployeesYear = 2011,
                Employees = 21,
                TurnoverYear = 2011,
                Turnover = 22,
                ActualAddress = await CreateAddressAsync(context, "41701")
            });

            await CreateLegalUnitAsync(context, new LegalUnit
            {
                UserId = "42",
                Name = Guid.NewGuid().ToString(),
                FreeEconZone = true,
                EmployeesYear = 2012,
                Employees = 22,
                TurnoverYear = 2012,
                Turnover = 220,
                ActualAddress = await CreateAddressAsync(context, "41702")
            });

            await CreateLegalUnitAsync(context, new LegalUnit
            {
                UserId = "42",
                Name = Guid.NewGuid().ToString(),
                FreeEconZone = true,
                EmployeesYear = 2012,
                Employees = 22,
                TurnoverYear = 2012,
                Turnover = 230,
                ActualAddress = await CreateAddressAsync(context, "41702")
            });
        }

        private static async Task CreateLegalUnitAsync(NSCRegDbContext context, LegalUnit legalUnit)
        {
            context.LegalUnits.Add(legalUnit);
            await context.SaveChangesAsync();

            var activity = await CreateActivityAsync(context);

            context.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
            {
                ActivityId = activity.Id,
                UnitId = (await context.LegalUnits.FirstOrDefaultAsync(x => x.Name == legalUnit.Name)).RegId
            });
            await context.SaveChangesAsync();
        }

        private static async Task<Address> CreateAddressAsync(NSCRegDbContext context, string code)
        {
            var region = context.Regions.Add(new Region
            {
                Code = code,
                Name = "Test region"
            });
            await context.SaveChangesAsync();

            var address = context.Address.Add(new Address
            {
                Region = region.Entity,
                AddressPart1 = Guid.NewGuid().ToString()
            });
            await context.SaveChangesAsync();

            return address.Entity;
        }

        private static async Task<Activity> CreateActivityAsync(NSCRegDbContext context)
        {
            var activity = context.Activities.Add(new Activity
            {
                ActivityYear = 2017,
                Employees = 888,
                Turnover = 2000000,
                ActivityCategory = new ActivityCategory
                {
                    Code = "Code",
                    Name = "Activity Category",
                    Section = "A"
                },
                ActivityType = ActivityTypes.Secondary,
                UpdatedBy = "Test"
            });
            await context.SaveChangesAsync();

            return activity.Entity;
        }
    }
}
