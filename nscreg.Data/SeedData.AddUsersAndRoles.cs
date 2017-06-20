using System;
using System.Linq;
using System.Reflection;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Attributes;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddUsersAndRoles(NSCRegDbContext context)
        {
            var sysAdminRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);

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
        }
    }
}
