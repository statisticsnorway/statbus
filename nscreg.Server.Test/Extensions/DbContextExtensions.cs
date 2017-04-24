using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Services;

namespace nscreg.Server.Test.Extensions
{
    public static class DbContextExtensions
    {
        public static readonly List<string> DataAccessEnterpriseGroup =
            DataAccessAttributesProvider<EnterpriseGroup>.Attributes.Select(v => v.Name).ToList();
        public static readonly List<string> DataAccessEnterpriseUnit =
            DataAccessAttributesProvider<EnterpriseUnit>.Attributes.Select(v => v.Name).ToList();
        public static readonly List<string> DataAccessLegalUnit =
            DataAccessAttributesProvider<LegalUnit>.Attributes.Select(v => v.Name).ToList();

        public static readonly List<string> DataAccessLocalUnit =
            DataAccessAttributesProvider<LocalUnit>.Attributes.Select(v => v.Name).ToList();


        public static string UserId => "8A071342-863E-4EFB-9B60-04050A6D2F4B";
        public static void Initialize(this NSCRegDbContext context)
        {
            var role = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);
            var daa = DataAccessAttributesProvider.Attributes.Select(v => v.Name).ToArray();
            if (role == null)
            {
                role = new Role
                {
                    Name = DefaultRoleNames.SystemAdministrator,
                    Status = RoleStatuses.Active,
                    Description = "System administrator role",
                    NormalizedName = DefaultRoleNames.SystemAdministrator.ToUpper(),
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions))).Cast<int>(),
                    //StandardDataAccessArray = daa,
                };
                context.Roles.Add(role);
            }
            var anyAdminHere = context.UserRoles.Any(ur => ur.RoleId == role.Id);
            if (anyAdminHere) return;
            var sysAdminUser = context.Users.FirstOrDefault(u => u.Login == "admin");
            if (sysAdminUser == null)
            {
                sysAdminUser = new User
                {
                    Id = UserId,
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
                RoleId = role.Id,
                UserId = sysAdminUser.Id
            };
            context.UserRoles.Add(adminUserRoleBinding);
            context.SaveChanges();
        }
    }
}