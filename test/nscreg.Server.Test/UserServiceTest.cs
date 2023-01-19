using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common;
using nscreg.Server.Common.Models.Users;
using nscreg.Server.Common.Services;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test
{
    public class UserServiceTest
    {
        private static IMapper CreateMapper() => new MapperConfiguration(mc =>
            mc.AddMaps(typeof(Startup).Assembly)).CreateMapper();

        public UserServiceTest()
        {
        }

        [Fact]
        public async void GetAllPaged()
        {
            Localization.Language1 = "ru-RU";
            Localization.Language2 = "ky-KG";
            using (var context = CreateDbContext())
            {
                const int expected = 10;
                for (var i = 0; i < expected; i++)
                {
                    var user = new User {Name = "Name_" + i, Status = UserStatuses.Active};
                    context.Users.Add(user);
                    var role = new Role {Name = DefaultRoleNames.Administrator, Status = RoleStatuses.Active};
                    context.Roles.Add(role);
                    context.UserRoles.Add(new UserRole(){RoleId = role.Id, UserId = user.Id});
                    context.Regions.AddRange(
                        new Region { Code = "41744000000000", Name = "Ак-Талинская область", AdminstrativeCenter = "г.Ак-Тала" },
                        new Region { Code = "41702000000000", Name = "Иссык-Кульская область", AdminstrativeCenter = "г.Каракол'" },
                        new Region { Code = "41703000000000", Name = "Джалал-Абадская область", AdminstrativeCenter = "г.Джалал-Абад" },
                        new Region { Code = "41704000000000", Name = "Нарынская область", AdminstrativeCenter = "г.Нарын" },
                        new Region { Code = "41705000000000", Name = "Баткенская область", AdminstrativeCenter = "г.Баткен" },
                        new Region { Code = "41706000000000", Name = "Ошская область", AdminstrativeCenter = "г.Ош" },
                        new Region { Code = "41707000000000", Name = "Таласская область", AdminstrativeCenter = "г.Талас" },
                        new Region { Code = "41708000000000", Name = "Чуйская область", AdminstrativeCenter = "г.Бишкек" },
                        new Region { Code = "41709000000000", Name = "Сусумырская область", AdminstrativeCenter = "г.Сусамыр" },
                        new Region { Code = "41710000000000", Name = "Ак-Маралская область", AdminstrativeCenter = "г.Ак-Марал" });

                    context.UserRegions.Add(new UserRegion
                    {
                        UserId = i.ToString(),
                        Region = new Region{Id = i},
                        RegionId = i,
                    });
                }
                context.SaveChanges();

                var userList = await new UserService(context, CreateMapper()).GetAllPagedAsync(new UserListFilter()
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
                var role = new Role {Name = DefaultRoleNames.Administrator, Status = RoleStatuses.Active};
                context.Roles.Add(role);
                context.Users.Add(user);
                context.UserRoles.Add(new UserRole(){RoleId = role.Id, UserId = user.Id});
                context.SaveChanges();

                //var expected = new UserService(context).GetUserVmById(user.Id);

                //Assert.Equal(expected.Name,
                //    context.Users.Single(x => x.Id == user.Id && x.UserName == user.UserName).Name);
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
                    UserRoles = new List<UserRole> { new UserRole(){RoleId = role.Id }}
                };
                ctx.Users.Add(user);
                ctx.SaveChanges();

                //var result = new UserService(ctx).GetUserVmById(user.Id);

                //Assert.Equal(role.Name, result.AssignedRole);
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
                    UserRoles = new List<UserRole> { new UserRole(){RoleId = sysRole.Id }}
                };
                var user2 = new User
                {
                    Name = "Name1",
                    UserName = "Login1",
                    Status = UserStatuses.Active,
                    UserRoles = new List<UserRole> { new UserRole(){RoleId = sysRole.Id }}
                };
                context.Users.AddRange(user, user2);
                context.SaveChanges();

                await new UserService(context,CreateMapper()).SetUserStatus(user.Id, true);

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
                    UserRoles = new List<UserRole> { new UserRole(){RoleId = sysRole.Id }}
                };
                context.Users.Add(user);
                context.SaveChanges();

                await new UserService(context, CreateMapper()).SetUserStatus(user.Id, false);

                Assert.Equal(UserStatuses.Active, context.Users.Single(x => x.Id == user.Id).Status);
            }
        }
    }
}
