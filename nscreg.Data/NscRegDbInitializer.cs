using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace nscreg.Data
{
    public static class NscRegDbInitializer
    {
        public static void RecreateDb(NSCRegDbContext context)
        {
            context.Database.EnsureDeleted();
            context.Database.Migrate();
        }

        public static void Seed(NSCRegDbContext context)
        {
            var sysAdminRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);
            var daa = typeof(EnterpriseGroup).GetProperties().Select(x => $"{nameof(EnterpriseGroup)}.{x.Name}")
                .Union(typeof(EnterpriseUnit).GetProperties().Select(x => $"{nameof(EnterpriseUnit)}.{x.Name}"))
                .Union(typeof(LegalUnit).GetProperties().Select(x => $"{nameof(LegalUnit)}.{x.Name}"))
                .Union(typeof(LocalUnit).GetProperties().Select(x => $"{nameof(LocalUnit)}.{x.Name}")).ToArray();
            if (sysAdminRole == null)
            {
                sysAdminRole = new Role
                {
                    Name = DefaultRoleNames.SystemAdministrator,
                    Status = RoleStatuses.Active,
                    Description = "System administrator role",
                    NormalizedName = DefaultRoleNames.SystemAdministrator.ToUpper(),
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions))).Select(x => (int) x),
                    StandardDataAccessArray = daa,
                };
                context.Roles.Add(sysAdminRole);
            }
            var anyAdminHere = context.UserRoles.Any(ur => ur.RoleId == sysAdminRole.Id);
            if (anyAdminHere) return;
            var sysAdminUser = context.Users.FirstOrDefault(u => u.Login == "admin");
            if (sysAdminUser == null)
            {
                sysAdminUser = new User
                {
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
                    DataAccessArray = daa,
                };
                context.Users.Add(sysAdminUser);
            }
            var adminUserRoleBinding = new IdentityUserRole<string>
            {
                RoleId = sysAdminRole.Id,
                UserId = sysAdminUser.Id,
            };
            context.UserRoles.Add(adminUserRoleBinding);
            var soateTmp = 741000000000000;
            if (!context.StatisticalUnits.Any())
            {
                context.StatisticalUnits.AddRange(new LocalUnit
                {
                    Name = "local unit 1",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address {AddressPart1 = "local address 1", GeographicalCodes = soateTmp++.ToString()}
                }, new LocalUnit
                {
                    Name = "local unit 2",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address {AddressPart1 = "local address 2", GeographicalCodes = soateTmp++.ToString() },
                });

                context.StatisticalUnits.AddRange(new LegalUnit
                {
                    Name = "legal unit 1",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address {AddressDetails = "legal address 1", GeographicalCodes = soateTmp++.ToString() },
                    ActivitiesUnits = new List<ActivityStatisticalUnit>()
                    {
                        new ActivityStatisticalUnit()
                        {
                            Activity = new Activity()
                            {
                                Turnover = 2000,
                                ActivityType = ActivityTypes.Primary,
                                UpdatedByUser = sysAdminUser,
                            },
                        },
                        new ActivityStatisticalUnit()
                        {
                            Activity =
                                new Activity()
                                {
                                    Turnover = 4000,
                                    ActivityType = ActivityTypes.Secondary,
                                    UpdatedByUser = sysAdminUser,
                                }
                        }
                    }
                }, new LegalUnit
                {
                    Name = "legal unit 2",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "legal address 2", GeographicalCodes = soateTmp++.ToString() }
                });
                context.StatisticalUnits.AddRange(new EnterpriseUnit
                {
                    Name = "enterprise unit 1",
                    RegIdDate = DateTime.Now,
                    IsDeleted = true,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "enterprise address 1", GeographicalCodes = soateTmp++.ToString() }
                }, new EnterpriseUnit
                {
                    Name = "enterprise unit 2",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "enterprise address 2", GeographicalCodes = soateTmp++.ToString() }
                }, new EnterpriseUnit
                {
                    Name = "enterprise unit 3",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "enterprise address 2", GeographicalCodes = soateTmp++.ToString() }
                }, new EnterpriseUnit
                {
                    Name = "enterprise unit 4",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "enterprise address 2", GeographicalCodes = soateTmp++.ToString() }
                }, new EnterpriseUnit
                {
                    Name = "enterprise unit 5",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "enterprise address 2", GeographicalCodes = soateTmp++.ToString() }
                }, new EnterpriseUnit
                {
                    Name = "enterprise unit 6",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "enterprise address 2", GeographicalCodes = soateTmp++.ToString() }
                });
                context.EnterpriseGroups.AddRange(new EnterpriseGroup
                {
                    Name = "enterprise group 1",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "ent. group address 1", GeographicalCodes = soateTmp++.ToString() }
                }, new EnterpriseGroup
                {
                    Name = "enterprise group 2",
                    IsDeleted = true,
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressDetails = "ent. group address 2", GeographicalCodes = soateTmp++.ToString() }
                });
            }

            if (!context.Regions.Any())
            {
                context.Regions.AddRange(
                    new Region { Name = "НСК/ГВЦ" },
                    new Region { Name = "Иссык-Кульский облстат" },
                    new Region { Name = "Джалал-Абадский облстат" },
                    new Region { Name = "Ала-Букинский райстат" },
                    new Region { Name = "Базар-Коргонский райстат" },
                    new Region { Name = "Баткенсктй облстат" },
                    new Region { Name = "Кадамжайский райстат" },
                    new Region { Name = "Нарынский облстат" },
                    new Region { Name = "Нарынский горстат" },
                    new Region { Name = "Жумгальский райстат" },
                    new Region { Name = "Ошский горстат" },
                    new Region { Name = "Бишкекский горстат" },
                    new Region { Name = "Аксуйский райстат" },
                    new Region { Name = "Жети-Огузский райстат" },
                    new Region { Name = "Иссык-Кульский райстат" },
                    new Region { Name = "Тонский райстат" },
                    new Region { Name = "Тюпский райстат" },
                    new Region { Name = "Балыкчинский горстат" },
                    new Region { Name = "Аксыйский райстат" },
                    new Region { Name = "Ноокенский райстат" },
                    new Region { Name = "Сузакский райстат" },
                    new Region { Name = "Тогуз-Тороуский райстат" },
                    new Region { Name = "Токтогульский райстат" },
                    new Region { Name = "Чаткальский райстат" },
                    new Region { Name = "Джалал-Абадский горстат" },
                    new Region { Name = "Таш-Кумырский горстат" },
                    new Region { Name = "Майлуу-Сууский горстат" },
                    new Region { Name = "Кара-Кульский горстат" },
                    new Region { Name = "Ак-Талинский райстат" },
                    new Region { Name = "Ат-Башынский райстат" },
                    new Region { Name = "Кочкорский райстат" },
                    new Region { Name = "Нарынский райстат" },
                    new Region { Name = "Баткенский райстат" },
                    new Region { Name = "Лейлекский райстат" },
                    new Region { Name = "Сулюктинский горстат" },
                    new Region { Name = "Ошский облстат" },
                    new Region { Name = "Алайский райстат" },
                    new Region { Name = "Араванский райстат" },
                    new Region { Name = "Кара-Сууский райстат" },
                    new Region { Name = "Ноокатский райстат" },
                    new Region { Name = "Кара-Кулжинский райстат" },
                    new Region { Name = "Узгенский райстат" },
                    new Region { Name = "Чон-Алайский райстат " },
                    new Region { Name = "Таласский облстат" },
                    new Region { Name = "Кара-Бууринский райстат" },
                    new Region { Name = "Бакай-Атинский райстат" },
                    new Region { Name = "Манасский райстат" },
                    new Region { Name = "Таласский райстат" },
                    new Region { Name = "Чуйский облстат" },
                    new Region { Name = "Аламудунский райстат" },
                    new Region { Name = "Ысык-Атинский райстат" },
                    new Region { Name = "Жайылский райстат" },
                    new Region { Name = "Кеминский райстат" },
                    new Region { Name = "Московский райстат" },
                    new Region { Name = "Панфиловский райстат" },
                    new Region { Name = "Сокулукский райстат" },
                    new Region { Name = "Чуйский райстат" },
                    new Region { Name = "Каракольский горстат" },
                    new Region { Name = "город Баткен" },
                    new Region { Name = "Кызыл-Киинский горстат" },
                    new Region { Name = "город Талас" },
                    new Region { Name = "город Токмок" }
                );
            }
            context.SaveChanges();
        }
    }
}
