using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.Linq;

namespace nscreg.Data
{
    public class NSCRegDbInitializer
    {
        private static NSCRegDbContext _context;

        public static void Initialize(IServiceProvider serviceProvider)
        {
            _context = (NSCRegDbContext)serviceProvider.GetService(typeof(NSCRegDbContext));
            Seed();
        }

        private static void Seed()
        {
            var sysAdminRole = _context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);
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
                _context.Roles.Add(sysAdminRole);
                _context.SaveChanges();
            }
            var anyAdminHere = _context.UserRoles.Any(ur => ur.RoleId == sysAdminRole.Id);
            if (!anyAdminHere)
            {
                var sysAdminUser = new User
                {
                    Login = "admin",
                    PasswordHash = "AQAAAAEAACcQAAAAELZgdj3JYQ5zZh4JD4m+0cVxwtH7W5c7enCYdXDxdzv+GmkhPp6UuTbchacUw6stEQ==",
                    Name = "adminName",
                    PhoneNumber = "555123456",
                    Email = "admin@email.xyz",
                    Status = UserStatuses.Active,
                    Description = "System administrator account",
                    NormalizedUserName = "admin".ToUpper(),
                    DataAccessArray = new[] { 1, 2 },
                };
                _context.UserRoles.Add(new IdentityUserRole<string> { UserId = sysAdminUser.Id, RoleId = sysAdminRole.Id });
                _context.SaveChanges();
            }
        }
    }
}
