using System;
using System.Linq;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Services;
using Xunit;

namespace nscreg.Server.Test
{
    public class UserServiceTest
    {
        [Fact]
        public void GetAllPaged()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                const int expected = 10;
                for (int i = 0; i < expected; i++)
                {
                    context.Users.Add(new User {Name = "Name_" + i, Status = UserStatuses.Active});
                }
                context.SaveChanges();

                var userList = new UserService(context).GetAllPaged(1, 1);

                Assert.Equal(expected, userList.TotalCount);
                Assert.Equal(expected, userList.TotalPages);
            }
        }

        [Fact]
        public void GetById()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                var user = new User {Name = "UserName", UserName = "UserLogin", Status = UserStatuses.Active};
                context.Users.Add(user);
                context.SaveChanges();

                var expected = new UserService(context).GetById(user.Id);

                Assert.Equal(expected.Name,
                    context.Users.Single(x => x.Id == user.Id && x.UserName == user.UserName).Name);
            }
        }

        [Fact]
        public void Suspend()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                var sysRole = new Role {Name = DefaultRoleNames.SystemAdministrator, Status = RoleStatuses.Active};
                context.Roles.Add(sysRole);
                context.SaveChanges();
                var user = new User
                {
                    Name = "Name",
                    UserName = "Login",
                    Status = UserStatuses.Active,
                    Roles = {new IdentityUserRole<string> {RoleId = sysRole.Id}}
                };
                context.Users.Add(user);
                context.SaveChanges();

                new UserService(context).Suspend(user.Id);

                Assert.Equal(UserStatuses.Suspended, context.Users.Single(x => x.Id == user.Id).Status);
            }
        }
    }
}