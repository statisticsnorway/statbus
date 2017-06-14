using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddStatUnits(NSCRegDbContext context)
        {
            var sysAdminUser = context.Users.FirstOrDefault(u => u.Name == DefaultRoleNames.SystemAdministrator);
            var regionTmp = 741000000000000;

            context.StatisticalUnits.AddRange(new LocalUnit
            {
                Name = "local unit 1",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address {AddressPart1 = "local address 1", GeographicalCodes = regionTmp++.ToString()}
            }, new LocalUnit
            {
                Name = "local unit 2",
                StatId = "OKPO2LU",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address {AddressPart1 = "local address 2", GeographicalCodes = regionTmp++.ToString()},
            });

            var le1 = new LegalUnit
            {
                Name = "legal unit 1",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StatId = "OKPO2LEGALU",
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "legal address 1",
                    GeographicalCodes = regionTmp++.ToString()
                },
                ActivitiesUnits = new List<ActivityStatisticalUnit>()
                {
                    new ActivityStatisticalUnit()
                    {
                        Activity = new Activity()
                        {
                            IdDate = new DateTime(2017, 03, 17),
                            Turnover = 2000,
                            ActivityType = ActivityTypes.Primary,
                            UpdatedByUser = sysAdminUser,
                            ActivityYear = DateTime.Today.Year,
                            ActivityRevxCategory = context.ActivityCategories.Single(v => v.Code == "11.07.9")
                        },
                    },
                    new ActivityStatisticalUnit()
                    {
                        Activity =
                            new Activity()
                            {
                                IdDate = new DateTime(2017, 03, 28),
                                Turnover = 4000,
                                ActivityType = ActivityTypes.Secondary,
                                UpdatedByUser = sysAdminUser,
                                ActivityYear = 2006,
                                ActivityRevxCategory = context.ActivityCategories.Single(v => v.Code == "91.01.9")
                            }
                    }
                }
            };

            context.StatisticalUnits.AddRange(le1, new LegalUnit
            {
                Name = "legal unit 2",
                UserId = sysAdminUser.Id,
                IsDeleted = true,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "legal address 2",
                    GeographicalCodes = regionTmp++.ToString()
                }
            });

            var eu1 = new EnterpriseUnit
            {
                Name = "enterprise unit 1",
                StatId = "OKPO1EU",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
            };

            var eu2 = new EnterpriseUnit
            {
                Name = "enterprise unit 2",
                StatId = "OKPO2EU",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "enterprise address 2",
                    GeographicalCodes = regionTmp++.ToString()
                }
            };

            context.EnterpriseUnits.AddRange(eu1, eu2, new EnterpriseUnit
            {
                Name = "enterprise unit 3",
                StatId = "OKPO3EU",
                UserId = sysAdminUser.Id,
                IsDeleted = true,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "enterprise address 2",
                    GeographicalCodes = regionTmp++.ToString()
                }
            }, new EnterpriseUnit
            {
                StatId = "OKPO4EU",
                Name = "enterprise unit 4",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "enterprise address 2",
                    GeographicalCodes = regionTmp++.ToString()
                }
            }, new EnterpriseUnit
            {
                Name = "enterprise unit 5",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "enterprise address 2",
                    GeographicalCodes = regionTmp++.ToString()
                }
            }, new EnterpriseUnit
            {
                Name = "enterprise unit 6",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address = new Address
                {
                    AddressDetails = "enterprise address 2",
                    GeographicalCodes = regionTmp++.ToString()
                }
            });

            var eg1 = new EnterpriseGroup
            {
                Name = "enterprise group 1",
                UserId = sysAdminUser.Id,
                StatId = "EG1",
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address =
                    new Address
                    {
                        AddressDetails = "ent. group address 1",
                        GeographicalCodes = regionTmp++.ToString()
                    }
            };

            var eg2 = new EnterpriseGroup
            {
                Name = "enterprise group 2",
                StatId = "EG2",
                UserId = sysAdminUser.Id,
                RegIdDate = DateTime.Now,
                StartPeriod = DateTime.Now,
                EndPeriod = DateTime.MaxValue,
                Address =
                    new Address
                    {
                        AddressDetails = "ent. group address 2",
                        GeographicalCodes = regionTmp++.ToString()
                    }
            };

            context.EnterpriseGroups.AddRange(eg1, eg2);

            //Links:
            eu1.EnterpriseGroup = eg1;
            le1.EnterpriseGroup = eg2;
            le1.EnterpriseUnit = eu1;
        }
    }
}
