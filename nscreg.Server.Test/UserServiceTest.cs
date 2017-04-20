using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Models;
using nscreg.Server.Models.Regions;
using nscreg.Server.Models.Users;
using nscreg.Server.Services;
using Xunit;
using static nscreg.Server.Test.InMemoryDb;

namespace nscreg.Server.Test
{
    public class UserServiceTest
    {

        public UserServiceTest()
        {
            AutoMapperConfiguration.Configure();
        }

        [Fact]
        public void GetAllPaged()
        {
            using (var context = CreateContext())
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

        [Theory]
        [InlineData("me_1", false, null, 11)]
        [InlineData("me_1", "Region 7", null, 1)]
        [InlineData(null, "Region 7", null, 4)]
        public async void GetFiltered(string username, string regionName, string roleId, int expectedRows)
        {
            using (var context = CreateContext())
            {
                var regionsService = new RegionsService(context);
                foreach (var name in new[] { "Test Region 1", "Test Region 2", "Region 7" })
                {
                    await regionsService.CreateAsync(new RegionM {Name = name});
                }
                var regions2 = await regionsService.ListAsync(v => v.Name != regionName);
                var targetRegions = await regionsService.ListAsync(v => v.Name == regionName);
                var target = targetRegions.SingleOrDefault();

                for (var i = 0; i <= 21; i++)
                {
                    context.Users.Add(new User
                    {
                        Name = "Name_" + i,
                        Status = UserStatuses.Active,
                        Region = i%7 == 0 ? target : regions2[i%2]
                    });
                    
                }
                await context.SaveChangesAsync();

                var userList = new UserService(context).GetAllPaged(new UserListFilter()
                {
                    UserName = username,
                    RegionId = target?.Id,
                    RoleId = roleId,
                    Page = 1,
                    PageSize = 50,
                });

                Assert.Equal(expectedRows, userList.Result.Count()); //UserName_14
            }
        }

        [Fact]
        public void GetById()
        {
            using (var context = CreateContext())
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
            using (var ctx = CreateContext())
            {
                var role = new Role {Name = DefaultRoleNames.SystemAdministrator, Status = RoleStatuses.Active};
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

                Assert.Equal(role.Name, result.AssignedRoles.First());
            }
        }

        [Fact]
        public async void Suspend()
        {
            using (var context = CreateContext())
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
            using (var context = CreateContext())
            {
                var sysRole = new Role { Name = DefaultRoleNames.SystemAdministrator, Status = RoleStatuses.Active };
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

        [Fact]
        public void RegisterUserWithRegion()
        {
            AutoMapperConfiguration.Configure();
            using (var ctx = CreateContext())
            {
                const string regionName = "Region 228";
                
                var region = new Region { Name = regionName };
                ctx.Regions.Add(region);
                ctx.SaveChanges();

                var user = new User
                {
                    Name = "user",
                    Status = UserStatuses.Active,
                    RegionId = region.Id
                };

                ctx.Users.Add(user);
                ctx.SaveChanges();

                var result = new UserService(ctx).GetById(user.Id);

                Assert.Equal(region.Id, result.RegionId);
            }
        }
    }
}
