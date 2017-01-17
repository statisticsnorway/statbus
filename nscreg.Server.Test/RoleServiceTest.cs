using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Models.Roles;
using nscreg.Server.Services;
using Xunit;

namespace nscreg.Server.Test
{
    public class RoleServiceTest
    {
        [Fact]
        public void GetAllPagedTest()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                const int expected = 10;
                for (var i = 0; i < expected; i++)
                {
                    context.Roles.Add(new Role {Name = "Role_" + i, Status = RoleStatuses.Active});
                }
                context.SaveChanges();

                var service = new RoleService(context).GetAllPaged(1, 1);

                Assert.Equal(expected, service.TotalCount);
                Assert.Equal(expected, service.TotalPages);
            }
        }

        [Fact]
        public void GetRoleByIdTest()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                const string roleName = "Role";
                context.Roles.Add(new Role {Name = roleName, Status = RoleStatuses.Active});
                context.SaveChanges();

                var role = new RoleService(context).GetRoleById(context.Roles.Single(x => x.Name == roleName).Id);

                Assert.Equal(roleName, role.Name);
            }
        }

        [Fact]
        public void GetUsersByRoleTest()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                const string userName = "User";
                var role = new Role {Name = "Role", Status = RoleStatuses.Active};
                context.Roles.Add(role);
                context.SaveChanges();
                context.Users.Add(new User
                {
                    Name = userName,
                    Status = UserStatuses.Active,
                    Roles = {new IdentityUserRole<string> {RoleId = role.Id}}
                });
                context.SaveChanges();

                var users = new RoleService(context).GetUsersByRole(role.Id);

                Assert.Equal(users.Single(x => x.Name == userName).Name, userName);
            }
        }

        [Fact]
        public void CreateTest()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                var submitData =
                    new RoleSubmitM
                    {
                        Name = "Role",
                        Description = "Description",
                        StandardDataAccess = new List<string> {"prop_1", "prop_2", "prop_3"},
                        AccessToSystemFunctions = new List<int> {1, 2, 3}
                    };

                var role = new RoleService(context).Create(submitData);
                var expected = typeof(Exception);
                Type actual = null;
                try
                {
                    new RoleService(context).Create(submitData);
                }
                catch (Exception e)
                {
                    actual = e.GetType();
                }

                Assert.Equal(role.Name,
                    context.Roles.Single(
                        x =>
                            x.Name == submitData.Name && x.Status == RoleStatuses.Active
                            && x.Description == submitData.Description
                            && x.StandardDataAccess == "prop_1,prop_2,prop_3"
                            && x.AccessToSystemFunctions == "1,2,3"
                    ).Name);
                Assert.Equal(expected, actual);
            }
        }

        [Fact]
        public void EditTest()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                var role = new Role {Name = "Role Name", Status = RoleStatuses.Active};
                context.Roles.Add(role);
                context.SaveChanges();
                context.Entry(role).State = EntityState.Detached;
                var roleData = new RoleSubmitM
                {
                    Name = "Edited Role Name",
                    AccessToSystemFunctions = new List<int> {1, 2, 3},
                    StandardDataAccess = new List<string> {"1", "2", "3"},
                    Description = "After Edit"
                };

                new RoleService(context).Edit(role.Id, roleData);
                var single = context.Roles.Single(x => x.Id == role.Id);

                Assert.Equal(roleData.Name, single.Name);
                Assert.Equal(role.Status, single.Status);
                Assert.Equal(roleData.Description, single.Description);
                Assert.Equal(roleData.AccessToSystemFunctions, single.AccessToSystemFunctionsArray);
                Assert.Equal(roleData.StandardDataAccess, single.StandardDataAccessArray);
            }
        }

        [Fact]
        public void SuspendTest()
        {
            using (var context = new NSCRegDbContext(InMemoryDb.GetContextOptions()))
            {
                var role = new Role {Name = "Role Name", Status = RoleStatuses.Active};
                context.Add(role);
                context.SaveChanges();

                new RoleService(context).Suspend(role.Id);

                Assert.Equal(RoleStatuses.Suspended, context.Roles.Single(x => x.Id == role.Id).Status);
            }
        }
    }
}