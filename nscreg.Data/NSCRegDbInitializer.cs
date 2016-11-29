using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Linq;

namespace nscreg.Data
{
    public class NSCRegDbInitializer
    {
        public static void Seed(NSCRegDbContext context, UserManager<User> userManager)
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
            if (!anyAdminHere)
            {
                var sysAdminUser = new User
                {
                    Login = "admin",
                    Name = "adminName",
                    PhoneNumber = "555123456",
                    Email = "admin@email.xyz",
                    Status = UserStatuses.Active,
                    Description = "System administrator account",
                    NormalizedUserName = "admin".ToUpper(),
                    DataAccessArray = new[] { 1, 2 },
                };
                context.Users.Add(sysAdminUser);
                var adminUserRoleBinding = new IdentityUserRole<string>
                {
                    RoleId = sysAdminRole.Id,
                    UserId = sysAdminUser.Id,
                };
                context.UserRoles.Add(adminUserRoleBinding);
                context.SaveChanges();
                var addPasswordResult = userManager.AddPasswordAsync(sysAdminUser, "123qwe").Result;
                if (!addPasswordResult.Succeeded)
                    throw new Exception(string.Join(".",
                        addPasswordResult.Errors.Select(err => $"{err.Code}: {err.Description}")));
            }
        }
    }
}
