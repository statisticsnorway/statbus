using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Attributes;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Utilities.Extensions;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddUsersAndRoles(NSCRegDbContext context)
        {
            var usedByServerFields = typeof(EnterpriseGroup).GetProperties()
                .Where(p => p.GetCustomAttribute<UsedByServerSideAttribute>() != null).Select(p => p.Name)
                .Union(typeof(EnterpriseUnit).GetProperties()
                    .Where(p => p.GetCustomAttribute<UsedByServerSideAttribute>() != null).Select(p => p.Name))
                .Union(typeof(LegalUnit).GetProperties()
                    .Where(p => p.GetCustomAttribute<UsedByServerSideAttribute>() != null).Select(p => p.Name))
                .Union(typeof(LocalUnit).GetProperties()
                    .Where(p => p.GetCustomAttribute<UsedByServerSideAttribute>() != null).Select(p => p.Name))
                .ToList();

            var daa = typeof(EnterpriseGroup).GetProperties()
                .Select(x => $"{nameof(EnterpriseGroup)}.{x.Name}")
                .Union(typeof(EnterpriseUnit).GetProperties()
                    .Select(x => $"{nameof(EnterpriseUnit)}.{x.Name}"))
                .Union(typeof(LegalUnit).GetProperties()
                    .Select(x => $"{nameof(LegalUnit)}.{x.Name}"))
                .Union(typeof(LocalUnit).GetProperties()
                    .Select(x => $"{nameof(LocalUnit)}.{x.Name}"))
                .ToArray();

            var adminRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.Administrator);
            if (adminRole == null)
            {
                adminRole = new Role
                {
                    Name = DefaultRoleNames.Administrator,
                    Status = RoleStatuses.Active,
                    Description = "System administrator role",
                    NormalizedName = DefaultRoleNames.Administrator.ToUpper(),
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions))).Select(x => (int) x),
                    StandardDataAccessArray =
                        new DataAccessPermissions(daa.Select(x =>
                            new Permission(x, true, !usedByServerFields.Any(x.Contains)))),
                };
                context.Roles.Add(adminRole);
            }
            else
            {
                adminRole.AccessToSystemFunctionsArray =
                    ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions))).Select(x => (int) x);
                adminRole.StandardDataAccessArray =
                    new DataAccessPermissions(daa.Select(x =>
                        new Permission(x, true, !usedByServerFields.Any(x.Contains))));
            }

            var employeeRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.Employee);
            if (employeeRole == null)
            {
                employeeRole = new Role
                {
                    Name = DefaultRoleNames.Employee,
                    Status = RoleStatuses.Active,
                    Description = "NSC employee role",
                    NormalizedName = DefaultRoleNames.Employee.ToUpper(),
                    AccessToSystemFunctionsArray = GetFunctionsForRole(DefaultRoleNames.Employee),
                    StandardDataAccessArray =
                        new DataAccessPermissions(daa.Select(x =>
                            new Permission(x, true, !usedByServerFields.Contains(x)))),
                };
                context.Roles.Add(employeeRole);
            }
            else
            {
                employeeRole.AccessToSystemFunctionsArray = GetFunctionsForRole(DefaultRoleNames.Employee);
                employeeRole.StandardDataAccessArray =
                    new DataAccessPermissions(daa.Select(x =>
                        new Permission(x, true, !usedByServerFields.Contains(x))));
            }

            var externalRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.ExternalUser);
            if (externalRole == null)
            {
                externalRole = new Role
                {
                    Name = DefaultRoleNames.ExternalUser,
                    Status = RoleStatuses.Active,
                    Description = "External user role",
                    NormalizedName = DefaultRoleNames.ExternalUser.ToUpper(),
                    AccessToSystemFunctionsArray = GetFunctionsForRole(DefaultRoleNames.ExternalUser),
                    StandardDataAccessArray =
                        new DataAccessPermissions(daa.Select(x => new Permission(x, true, false))),
                };
                context.Roles.Add(externalRole);
            }
            else
            {
                externalRole.AccessToSystemFunctionsArray = GetFunctionsForRole(DefaultRoleNames.ExternalUser);
                externalRole.StandardDataAccessArray =
                    new DataAccessPermissions(daa.Select(x => new Permission(x, true, false)));
            }

            var adminUser = context.Users.Where(u => u.Email == "admin@email.xyz").ToList();
            var sysAdminUser = adminUser.FirstOrDefault();

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

            if (!context.UserRoles.Any(x => x.RoleId == adminRole.Id && x.UserId == sysAdminUser.Id))
            {
                var adminUserRoleBinding = new UserRole
                {
                    RoleId = adminRole.Id,
                    UserId = sysAdminUser.Id,
                };
                context.UserRoles.Add(adminUserRoleBinding);
            }

            context.SaveChanges();
        }

        private static IEnumerable<int> GetFunctionsForRole(string role)
        {
            return EnumExtensions.GetMembers<SystemFunctions, AllowedToAttribute>(x =>
                x.IsAllowedTo(role)).Select(x => (int) x);
        }
    }
}
