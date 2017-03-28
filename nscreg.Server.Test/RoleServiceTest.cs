using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Models.DataAccess;
using nscreg.Server.Models.Roles;
using nscreg.Server.Services;
using Xunit;
using static nscreg.Server.Test.InMemoryDb;

namespace nscreg.Server.Test
{
    public class RoleServiceTest
    {
        [Fact]
        public void GetAllPagedTest()
        {
            using (var context = CreateContext())
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
            using (var context = CreateContext())
            {
                const string roleName = "Role";
                context.Roles.Add(new Role {Name = roleName, Status = RoleStatuses.Active});
                context.SaveChanges();

                var role = new RoleService(context).GetRoleById(context.Roles.Single(x => x.Name == roleName).Id);

                Assert.Equal(roleName, role.Name);
            }
        }

        [Fact]
        public void CreateTest()
        {
            using (var context = CreateContext())
            {
                var submitData =
                    new RoleSubmitM
                    {
                        Name = "Role",
                        Description = "Description",
                        StandardDataAccess = new DataAccessModel()
                        {
                            LocalUnit = new[] {new DataAccessAttributeModel("prop1", true) },
                            LegalUnit = new[] {new DataAccessAttributeModel("prop2", true) },
                            EnterpriseGroup = new[] {new DataAccessAttributeModel("prop3", true) },
                            EnterpriseUnit = new[] {new DataAccessAttributeModel("prop4", true) },
                        },
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
                            && x.StandardDataAccess == submitData.StandardDataAccess.ToString()
                            && x.AccessToSystemFunctions == "1,2,3"
                    ).Name);
                Assert.Equal(expected, actual);
            }
        }

        [Fact]
        public void EditTest()
        {
            using (var context = CreateContext())
            {
                var role = new Role
                {
                    AccessToSystemFunctionsArray = new List<int> {1, 3},
                    Name = "Role Name",
                    StandardDataAccessArray = new List<string> {"LocalUnit.1", "LegalUnit.2", "EnterpriseUnit.3", "EnterpriseGroup.4"},
                    Status = RoleStatuses.Active
                };
                context.Roles.Add(role);
                context.SaveChanges();
                context.Entry(role).State = EntityState.Detached;
                var roleData = new RoleSubmitM
                {
                    Name = "Edited Role Name",
                    AccessToSystemFunctions = new List<int> {1, 2, 3},
                    StandardDataAccess =  new DataAccessModel()
                    {
                        LocalUnit = new[] { new DataAccessAttributeModel("prop1", true) },
                        LegalUnit = new[] { new DataAccessAttributeModel("prop2", true) },
                        EnterpriseGroup = new[] { new DataAccessAttributeModel("prop3", true) },
                        EnterpriseUnit = new[] { new DataAccessAttributeModel("prop4", true) },
                    },
                    Description = "After Edit"
                };

                new RoleService(context).Edit(role.Id, roleData);
                var single = context.Roles.Single(x => x.Id == role.Id);

                Assert.Equal(roleData.Name, single.Name);
                Assert.Equal(role.Status, single.Status);
                Assert.Equal(roleData.Description, single.Description);
                Assert.Equal(roleData.AccessToSystemFunctions, single.AccessToSystemFunctionsArray);
                Assert.Equal(roleData.StandardDataAccess.ToString(), single.StandardDataAccess);
            }
        }

        [Fact]
        public async Task SuspendTest()
        {
            using (var context = CreateContext())
            {
                var role = new Role {Name = "Role Name", Status = RoleStatuses.Active};
                context.Add(role);
                context.SaveChanges();

                await new RoleService(context).Suspend(role.Id);

                Assert.Equal(RoleStatuses.Suspended, context.Roles.Single(x => x.Id == role.Id).Status);
            }
        }
    }
}
