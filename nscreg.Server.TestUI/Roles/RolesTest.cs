using System;
using OpenQA.Selenium;
using Xunit;

namespace nscreg.Server.TestUI.Roles
{
    public class RolesTest : IDisposable
    {
        private readonly IWebDriver _driver;
        private readonly string _roleNameField = "Manager";
        private readonly string _descriptionField = "Manager role";

        public RolesTest()
        {
            _driver = Setup.CreateWebDriver();
        }

        public void Dispose()
        {
            _driver.Quit();
        }

        [Fact]
        public void AddRole()
        {
            var home = new RolePage(_driver);

            RolePageResult resultRole = home.AddRoleAct(_roleNameField, _descriptionField);

            Assert.True(resultRole.AddRolePage().Contains(_roleNameField));
        }

        [Fact]
        public void EditRole()
        {
            var home = new RolePage(_driver);

            RolePageResult resultRole = home.EditRoleAct(_roleNameField, _descriptionField);

            Assert.True(resultRole.EditRolePage().Contains(_roleNameField));
        }

        [Fact]
        public void DeleteRole()
        {
            var home = new RolePage(_driver);

            RolePageResult resultRole = home.DeleteRoleAct();

            Assert.False(resultRole.DeleteRolePage().Contains(_roleNameField));
        }

        [Fact]
        public void UsersInRole()
        {
            var home = new RolePage(_driver);

            RolePageResult resultRole = home.DisplayUserAct();

            Assert.True(resultRole.DisplayRolePage());
        }
    }
}
