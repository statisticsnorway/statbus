using System;
using System.Linq;
using System.Reflection;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Attributes;
using nscreg.Data.Entities.ComplexTypes;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddUsersAndRoles(NSCRegDbContext context)
        {
            var daa = typeof(EnterpriseGroup).GetProperties()
                .Where(v => v.GetCustomAttribute<NotMappedForAttribute>() == null)
                .Select(x => $"{nameof(EnterpriseGroup)}.{x.Name}")
                .Union(typeof(EnterpriseUnit).GetProperties()
                    .Where(v => v.GetCustomAttribute<NotMappedForAttribute>() == null)
                    .Select(x => $"{nameof(EnterpriseUnit)}.{x.Name}"))
                .Union(typeof(LegalUnit).GetProperties()
                    .Where(v => v.GetCustomAttribute<NotMappedForAttribute>() == null)
                    .Select(x => $"{nameof(LegalUnit)}.{x.Name}"))
                .Union(typeof(LocalUnit).GetProperties()
                    .Where(v => v.GetCustomAttribute<NotMappedForAttribute>() == null)
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
                    StandardDataAccessArray = new DataAccessPermissions(daa.Select(x => new Permission(x, true, true))),
                };
                context.Roles.Add(adminRole);
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
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[])Enum.GetValues(typeof(SystemFunctions))).Select(x => (int)x),
                    StandardDataAccessArray = new DataAccessPermissions(daa.Select(x => new Permission(x, true, true))),
                };
                context.Roles.Add(employeeRole);
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
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[])Enum.GetValues(typeof(SystemFunctions))).Select(x => (int)x),
                    StandardDataAccessArray = new DataAccessPermissions(daa.Select(x => new Permission(x, true, false))),
                };
                context.Roles.Add(externalRole);
            }

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

            if (!context.UserRoles.Any(x=>x.RoleId == adminRole.Id && x.UserId == sysAdminUser.Id))
            {
                var adminUserRoleBinding = new IdentityUserRole<string>
                {
                    RoleId = adminRole.Id,
                    UserId = sysAdminUser.Id,
                };
                context.UserRoles.Add(adminUserRoleBinding);
            }

            context.SaveChanges();
        }
    }
}
