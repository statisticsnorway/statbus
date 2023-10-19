using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System.Linq;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddStatUnits(NSCRegDbContext context)
        {
            var roleId = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.Administrator)?.Id;
            var adminId = context.UserRoles.FirstOrDefault(x => x.RoleId == roleId)?.UserId;
            var sysAdminUser = context.Users.FirstOrDefault(u => u.Id == adminId);

            context.StatisticalUnits.AddRange(new LocalUnit
            {
                Name = "local unit 1",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address { AddressPart1 = "local address 1", RegionId = 1 },
            }, new LocalUnit
            {
                Name = "local unit 2",
                StatId = "OKPO2LU",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address { AddressPart1 = "local address 2", RegionId = 1 },
            });

            var le1 = new LegalUnit
            {
                Name = "legal unit 1",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StatId = "OKPO2LEGALU",
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "legal address 1",
                    RegionId = 1
                },
                ActivitiesUnits = new List<ActivityStatisticalUnit>
                {
                    new ActivityStatisticalUnit
                    {
                        Activity = new Activity
                        {
                            IdDate = new DateTimeOffset(new DateTime(2017, 03, 17)),
                            Turnover = 2000,
                            ActivityType = ActivityTypes.Primary,
                            UpdatedByUser = sysAdminUser,
                            ActivityYear = DateTimeOffset.UtcNow.Year,
                            ActivityCategory = context.ActivityCategories.Single(v => v.Code == "11.07.9")
                        },
                    },
                    new ActivityStatisticalUnit
                    {
                        Activity =
                            new Activity
                            {
                                IdDate = new DateTimeOffset(new DateTime(2017, 03, 28)),
                                Turnover = 4000,
                                ActivityType = ActivityTypes.Secondary,
                                UpdatedByUser = sysAdminUser,
                                ActivityYear = 2006,
                                ActivityCategory = context.ActivityCategories.Single(v => v.Code == "91.01.9")
                            }
                    }
                },
            };

            context.StatisticalUnits.AddRange(le1, new LegalUnit
            {
                Name = "legal unit 2",
                UserId = sysAdminUser.Id,
                IsDeleted = true,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "legal address 2",
                    RegionId = 1
                },
            });

            var eu1 = new EnterpriseUnit
            {
                Name = "enterprise unit 1",
                StatId = "OKPO1EU",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
            };

            var eu2 = new EnterpriseUnit
            {
                Name = "enterprise unit 2",
                StatId = "OKPO2EU",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "enterprise address 2",
                    RegionId = 1
                },
            };

            context.EnterpriseUnits.AddRange(eu1, eu2, new EnterpriseUnit
            {
                Name = "enterprise unit 3",
                StatId = "OKPO3EU",
                UserId = sysAdminUser.Id,
                IsDeleted = true,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "enterprise address 2",
                    RegionId = 1
                },
            }, new EnterpriseUnit
            {
                StatId = "OKPO4EU",
                Name = "enterprise unit 4",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "enterprise address 2",
                    RegionId = 1
                },
            }, new EnterpriseUnit
            {
                Name = "enterprise unit 5",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "enterprise address 2",
                    RegionId = 1
                },
            }, new EnterpriseUnit
            {
                Name = "enterprise unit 6",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress = new Address
                {
                    AddressPart1 = "enterprise address 2",
                    RegionId = 1
                },
            });

            var eg1 = new EnterpriseGroup
            {
                Name = "enterprise group 1",
                UserId = sysAdminUser.Id,
                StatId = "EG1",
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress =
                    new Address { AddressPart1 = "ent. group address 1", RegionId = 1 },
            };

            var eg2 = new EnterpriseGroup
            {
                Name = "enterprise group 2",
                StatId = "EG2",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTimeOffset.Now,
                StartPeriod = DateTimeOffset.Now,
                EndPeriod = DateTimeOffset.MaxValue,
                ActualAddress =
                    new Address { AddressPart1 = "ent. group address 2", RegionId = 1 }
            };

            context.EnterpriseGroups.AddRange(eg1, eg2);

            //Links:
            eu1.EnterpriseGroup = eg1;
            le1.EnterpriseUnit = eu1;

            context.SaveChanges();
        }
    }
}
