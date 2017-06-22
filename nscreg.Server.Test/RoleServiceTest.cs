using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Server.Common.Models.Roles;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Utilities;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test
{
    public class RoleServiceTest
    {
        public RoleServiceTest()
        {
            StartupConfiguration.ConfigureAutoMapper();
        }

        [Fact]
        public void GetAllPagedTest()
        {
            using (var context = CreateDbContext())
            {
                const int expected = 10;
                for (var i = 0; i < expected; i++)
                {
                    context.Roles.Add(new Role {Name = "Role_" + i, Status = RoleStatuses.Active});
                }
                context.SaveChanges();

                var service = new RoleService(context).GetAllPaged(new PaginationModel {Page = 1, PageSize = 1}, true);

                Assert.Equal(expected, service.TotalCount);
                Assert.Equal(expected, service.TotalPages);
            }
        }

        [Fact]
        public void GetRoleByIdTest()
        {
            using (var context = CreateDbContext())
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
            using (var context = CreateDbContext())
            {
                var submitData =
                    new RoleSubmitM
                    {
                        Name = "Role",
                        Description = "Description",
                        StandardDataAccess = new DataAccessModel()
                        {
                            LocalUnit = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<LegalUnit>("ForeignCapitalShare"), Allowed = true } },
                            LegalUnit = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<LocalUnit>("FreeEconZone"), Allowed = true } },
                            EnterpriseGroup = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<EnterpriseGroup>("LiqReason"), Allowed = true } },
                            EnterpriseUnit = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<EnterpriseUnit>("Employees"), Allowed = true } },
                        },
                        AccessToSystemFunctions = new List<int> {1, 2, 3},
                        ActiviyCategoryIds = new int[] {}
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
            using (var context = CreateDbContext())
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

                var daa = new DataAccessModel()
                {
                    LocalUnit = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<LegalUnit>("ForeignCapitalShare") , Allowed = true } },
                    LegalUnit = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName <LocalUnit>("FreeEconZone"), Allowed = true } },
                    EnterpriseGroup = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<EnterpriseGroup>("LiqReason"), Allowed = true } },
                    EnterpriseUnit = new List<DataAccessAttributeVm>() { new DataAccessAttributeVm { Name = DataAccessAttributesHelper.GetName<EnterpriseUnit>("Employees"), Allowed = true } },
                };

                var roleData = new RoleSubmitM
                {
                    Name = "Edited Role Name",
                    AccessToSystemFunctions = new List<int> {1, 2, 3},
                    StandardDataAccess =  daa,
                    Description = "After Edit",
                    ActiviyCategoryIds = new int[] { }
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
            using (var context = CreateDbContext())
            {
                var role = new Role {Name = "Role Name", Status = RoleStatuses.Active};
                context.Add(role);
                context.SaveChanges();

                await new RoleService(context).ToggleSuspend(role.Id, RoleStatuses.Suspended);

                Assert.Equal(RoleStatuses.Suspended, context.Roles.Single(x => x.Id == role.Id).Status);
            }
        }
    }
}
