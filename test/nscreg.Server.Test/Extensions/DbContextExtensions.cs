using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Identity;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Test.Extensions
{
    public static class DbContextExtensions
    {
        public static readonly DataAccessPermissions DataAccessEnterpriseGroup =
            new DataAccessPermissions(DataAccessAttributesProvider<EnterpriseGroup>.Attributes
                .Select(v => new Permission(v.Name, true, true)));

        public static readonly DataAccessPermissions DataAccessEnterpriseUnit =
            new DataAccessPermissions(DataAccessAttributesProvider<EnterpriseUnit>.Attributes
                .Select(v => new Permission(v.Name, true, true)));

        public static readonly DataAccessPermissions DataAccessLegalUnit =
            new DataAccessPermissions(DataAccessAttributesProvider<LegalUnit>.Attributes
                .Select(v => new Permission(v.Name, true, true)));

        public static readonly DataAccessPermissions DataAccessLocalUnit =
            new DataAccessPermissions(DataAccessAttributesProvider<LocalUnit>.Attributes
                .Select(v => new Permission(v.Name, true, true)));

        public static string UserId => "8A071342-863E-4EFB-9B60-04050A6D2F4B";

        public static void Initialize(this NSCRegDbContext context)
        {
            ElasticService.ServiceAddress = "http://localhost:9200";
            ElasticService.StatUnitSearchIndexName = "statunitsearchviewtest";
            var role = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.Administrator);
            var daa = DataAccessAttributesProvider.Attributes.Select(v => v.Name).ToArray();
            if (role == null)
            {
                role = new Role
                {
                    Name = DefaultRoleNames.Administrator,
                    Status = RoleStatuses.Active,
                    Description = "System administrator role",
                    NormalizedName = DefaultRoleNames.Administrator.ToUpper(),
                    AccessToSystemFunctionsArray =
                        ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions))).Cast<int>(),
                    StandardDataAccessArray = new DataAccessPermissions(
                        new List<string> { "LocalUnit.1", "LegalUnit.2", "EnterpriseUnit.3", "EnterpriseGroup.4" }
                            .Select(x => new Permission(x, true, true)))
                };
                context.Roles.Add(role);
            }

            context.Roles.Add(new Role()
            {
                Name = DefaultRoleNames.Employee,
                Status = RoleStatuses.Active,
                Description = "Employee",
                NormalizedName = DefaultRoleNames.Employee.ToUpper(),
                AccessToSystemFunctionsArray = ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions))).Cast<int>(),
                StandardDataAccessArray = null
            });
            var anyAdminHere = context.UserRoles.Any(ur => ur.RoleId == role.Id);
            if (anyAdminHere) return;
            var sysAdminUser = context.Users.FirstOrDefault(u => u.UserName == "admin");
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
                    DataAccessArray = daa
                };
                context.Users.Add(sysAdminUser);
            }
            var adminUserRoleBinding = new UserRole
            {
                RoleId = role.Id,
                UserId = sysAdminUser.Id
            };
            context.UserRoles.Add(adminUserRoleBinding);
            context.SaveChanges();
        }
    }
}
