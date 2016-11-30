using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System.Linq;

namespace nscreg.Data
{
    public class NSCRegDbInitializer
    {
        public static void Seed(NSCRegDbContext context)
        {
            var sysAdminRole = context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);
            if (sysAdminRole == null)
            {
                sysAdminRole = new Role
                {
                    Name = DefaultRoleNames.SystemAdministrator,
                    Description = "System administrator role",
                    NormalizedName = DefaultRoleNames.SystemAdministrator.ToUpper(),
                    AccessToSystemFunctionsArray = new[] { (int)SystemFunction.AddUser },
                    StandardDataAccessArray = new[] { 1, 2 },
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
                    PasswordHash = "AQAAAAEAACcQAAAAEF+cTdTv1Vbr9+QFQGMo6E6S5aGfoFkBnsrGZ4kK6HIhI+A9bYDLh24nKY8UL3XEmQ==",
                    SecurityStamp = "9479325a-6e63-494a-ae24-b27be29be015",
                    Name = "Admin user",
                    PhoneNumber = "555123456",
                    Email = "admin@email.xyz",
                    NormalizedEmail = "admin@email.xyz".ToUpper(),
                    Status = UserStatuses.Active,
                    Description = "System administrator account",
                    NormalizedUserName = "admin".ToUpper(),
                    DataAccessArray = new[] { 1, 2 },
                };
                context.Users.Add(sysAdminUser);
            }
            var adminUserRoleBinding = new IdentityUserRole<string>
            {
                RoleId = sysAdminRole.Id,
                UserId = sysAdminUser.Id,
            };
            context.UserRoles.Add(adminUserRoleBinding);
            context.SaveChanges();
        }
    }
}
