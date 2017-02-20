using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Remotion.Linq.Parsing.Structure.ExpressionTreeProcessors;

namespace nscreg.Data
{
    public static class NscRegDbInitializer
    {
        public static void Seed(NSCRegDbContext context)
        {
            var sysAdminRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);
            var daa = typeof(StatisticalUnit).GetProperties().Select(x => x.Name)
                .Union(typeof(EnterpriseGroup).GetProperties().Select(x => x.Name))
                .Union(typeof(EnterpriseUnit).GetProperties().Select(x => x.Name))
                .Union(typeof(LegalUnit).GetProperties().Select(x => x.Name))
                .Union(typeof(LocalUnit).GetProperties().Select(x => x.Name)).ToArray();
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

            context.ReportingViews.AddRange(new ReportingView
                {
                    Name = "Reporting View 1"
                }, new ReportingView
                {
                    Name = "Reporting View 2"
                }
            );
           

            if (!context.StatisticalUnits.Any())
            {
                context.StatisticalUnits.AddRange(new LocalUnit
                {
                    Name = "local unit 1",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "local address 1" }
                }, new LocalUnit
                {
                    Name = "local unit 2",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "local address 2" },
                });

                context.StatisticalUnits.AddRange(new LegalUnit
                {
                    Name = "legal unit 1",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "legal address 1" }
                }, new LegalUnit
                {
                    Name = "legal unit 2",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "legal address 2" }
                });
                context.StatisticalUnits.AddRange(new EnterpriseUnit
                {
                    Name = "enterprise unit 1",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "enterprise address 1" }
                }, new EnterpriseUnit
                {
                    Name = "enterprise unit 2",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "enterprise address 2" }
                });
                context.EnterpriseGroups.AddRange(new EnterpriseGroup
                {
                    Name = "enterprise group 1",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "ent. group address 1" }
                }, new EnterpriseGroup
                {
                    Name = "enterprise group 2",
                    RegIdDate = DateTime.Now,
                    StartPeriod = DateTime.Now,
                    EndPeriod = DateTime.MaxValue,
                    Address = new Address { AddressPart1 = "ent. group address 2" }
                });
            }
            context.SaveChanges();

            var reportingViews = context.ReportingViews.ToList();

            var localUnit = context.StatisticalUnits.ToList().FirstOrDefault(x=> x.UnitType == StatUnitTypes.LocalUnit);
            CreateReportingViewLinkFor(localUnit, reportingViews.FirstOrDefault(x=> x.Name == "Reporting View 1"), context);

            var legalUnit = context.StatisticalUnits.ToList().FirstOrDefault(x => x.UnitType == StatUnitTypes.LegalUnit);
            CreateReportingViewLinkFor(legalUnit, reportingViews.FirstOrDefault(x => x.Name == "Reporting View 2"), context);

            var enterpriseUnit = context.StatisticalUnits.ToList().FirstOrDefault(x => x.UnitType == StatUnitTypes.EnterpriseUnit);
            CreateReportingViewLinkFor(enterpriseUnit, reportingViews.FirstOrDefault(x => x.Name == "Reporting View 1"), context);
            
        }

        private static void CreateReportingViewLinkFor(StatisticalUnit unit, ReportingView reportingView, NSCRegDbContext context)
        {
            unit.ReportingViews = new List<StatisticalUnitReportingView>
            {
                new StatisticalUnitReportingView
                {
                    ReportingView = reportingView,
                    RepViewId = reportingView.Id,
                    StatisticalUnit = unit,
                    StatId = unit.StatId
                }
            };
            context.SaveChanges();
        }
    }
}
