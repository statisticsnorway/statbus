using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Users;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test
{
    public class UserServiceTest
    {

        public UserServiceTest()
        {
            StartupConfiguration.ConfigureAutoMapper();
        }

        [Fact]
        public void GetAllPaged()
        {
            using (var context = CreateDbContext())
            {
                const int expected = 10;
                for (var i = 0; i < expected; i++)
                {
                    context.Users.Add(new User {Name = "Name_" + i, Status = UserStatuses.Active});
                }
                context.SaveChanges();

                var userList = new UserService(context).GetAllPaged(new UserListFilter()
                {
                    Page = 2,
                    PageSize = 4,
                });

                Assert.Equal(expected, userList.TotalCount);
                Assert.Equal(3, userList.TotalPages);
            }
        }

        [Fact]
        public void GetById()
        {
            using (var context = CreateDbContext())
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
        public void GetByIdShouldReturnWithRoles()
        {
            using (var ctx = CreateDbContext())
            {
                var role = new Role {Name = DefaultRoleNames.Administrator, Status = RoleStatuses.Active};
                ctx.Roles.Add(role);
                ctx.SaveChanges();
                var user = new User
                {
                    Name = "user",
                    Status = UserStatuses.Active,
                    Roles = {new IdentityUserRole<string> {RoleId = role.Id}}
                };
                ctx.Users.Add(user);
                ctx.SaveChanges();

                var result = new UserService(ctx).GetById(user.Id);

                Assert.Equal(role.Name, result.AssignedRole);
            }
        }

        [Fact]
        public async void Suspend()
        {
            using (var context = CreateDbContext())
            {
                var sysRole = new Role {Name = DefaultRoleNames.Administrator, Status = RoleStatuses.Active};
                context.Roles.Add(sysRole);
                context.SaveChanges();
                var user = new User
                {
                    Name = "Name",
                    UserName = "Login",
                    Status = UserStatuses.Active,
                    Roles = {new IdentityUserRole<string> {RoleId = sysRole.Id}}
                };
                var user2 = new User
                {
                    Name = "Name1",
                    UserName = "Login1",
                    Status = UserStatuses.Active,
                    Roles = { new IdentityUserRole<string> { RoleId = sysRole.Id } }
                };
                context.Users.AddRange(user, user2);
                context.SaveChanges();

                await new UserService(context).SetUserStatus(user.Id, true);

                Assert.Equal(UserStatuses.Suspended, context.Users.Single(x => x.Id == user.Id).Status);
            }
        }

        [Fact]
        public async void Unsuspend()
        {
            using (var context = CreateDbContext())
            {
                var sysRole = new Role { Name = DefaultRoleNames.Administrator, Status = RoleStatuses.Active };
                context.Roles.Add(sysRole);
                context.SaveChanges();
                var user = new User
                {
                    Name = "Name1",
                    UserName = "Login1",
                    Status = UserStatuses.Suspended,
                    Roles = { new IdentityUserRole<string> { RoleId = sysRole.Id } }
                };
                context.Users.Add(user);
                context.SaveChanges();

                await new UserService(context).SetUserStatus(user.Id, false);

                Assert.Equal(UserStatuses.Active, context.Users.Single(x => x.Id == user.Id).Status);
            }
        }
    }
}
