using System;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Server.Test.Extensions;
using nscreg.Utilities.Enums.SampleFrame;
using nscreg.Utilities.Models.SampleFrame;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test
{
    public class SampleFrameServiceTest
    {
        public SampleFrameServiceTest()
        {
            StartupConfiguration.ConfigureAutoMapper();
        }
        
        [Fact]
        public async Task Create()
        {
            using (var context = CreateDbContext())
            {
                context.Initialize();
                
                await CreateStatisticalUnitsAsync(context);
                var expression = new SFExpression
                {
                    ExpressionItem = null,
                    FirstSfExpression = new SFExpression
                    {
                        FirstSfExpression = new SFExpression
                        {
                            ExpressionItem = new ExpressionItem
                            {
                                Field = FieldEnum.Region,
                                Value = "41701",
                                Operation = OperationEnum.Equal
                            }
                        },
                        Comparison = ComparisonEnum.And,
                        SecondSfExpression = new SFExpression
                        {
                            ExpressionItem = new ExpressionItem
                            {
                                Field = FieldEnum.Status,
                                Value = StatUnitStatuses.Active,
                                Operation = OperationEnum.Equal
                            }
                        },
                    },
                    Comparison = ComparisonEnum.AndNot,
                    SecondSfExpression = new SFExpression
                    {
                        ExpressionItem = null,
                        FirstSfExpression = new SFExpression
                        {
                            ExpressionItem = new ExpressionItem
                            {
                                Field = FieldEnum.MainActivity,
                                Value = 4,
                                Operation = OperationEnum.Equal
                            }
                        },
                        Comparison = ComparisonEnum.OrNot,
                        SecondSfExpression = new SFExpression
                        {
                            ExpressionItem = new ExpressionItem
                            {
                                Field = FieldEnum.Turnover,
                                Value = 210,
                                Operation = OperationEnum.LessThanOrEqual
                            }
                        }
                    }
                };
                await new SampleFrameService(context).Create(expression);
            }
        }

        private static async Task CreateStatisticalUnitsAsync(NSCRegDbContext context)
        {
            await CreateLegalUnitAsync(context, new LegalUnit
            {
                Name = Guid.NewGuid().ToString(),
                ForeignParticipation = "Yes",
                FreeEconZone = true,
                EmployeesYear = 2010,
                Employees = 20,
                TurnoverYear = 2010,
                Turnover = 200,
                Status = StatUnitStatuses.Active,
                Address = await CreateAddressAsync(context, "41701")
            });

            await CreateLegalUnitAsync(context, new LegalUnit
            {
                Name = Guid.NewGuid().ToString(),
                ForeignParticipation = "No",
                FreeEconZone = true,
                EmployeesYear = 2011,
                Employees = 21,
                TurnoverYear = 2011,
                Turnover = 210,
                Status = StatUnitStatuses.Active,
                Address = await CreateAddressAsync(context, "41701")
            });

            await CreateLegalUnitAsync(context, new LegalUnit
            {
                Name = Guid.NewGuid().ToString(),
                ForeignParticipation = "Yes",
                FreeEconZone = true,
                EmployeesYear = 2012,
                Employees = 22,
                TurnoverYear = 2012,
                Turnover = 220,
                Status = StatUnitStatuses.Active,
                Address = await CreateAddressAsync(context, "41702")
            });

            await CreateLegalUnitAsync(context, new LegalUnit
            {
                Name = Guid.NewGuid().ToString(),
                ForeignParticipation = "Yes",
                FreeEconZone = true,
                EmployeesYear = 2012,
                Employees = 22,
                TurnoverYear = 2012,
                Turnover = 230,
                Status = StatUnitStatuses.Active,
                Address = await CreateAddressAsync(context, "41702")
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
                UnitId = context.LegalUnits.FirstOrDefault(x => x.Name == legalUnit.Name).RegId
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
                ActivityRevxCategory = new ActivityCategory
                {
                    Code = "Code",
                    Name = "Activity Category",
                    Section = "A"
                },
                ActivityRevy = 3,
                ActivityType = ActivityTypes.Secondary
            });
            await context.SaveChangesAsync();

            return activity.Entity;
        }
    }
}
