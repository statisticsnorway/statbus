using System;
using nscreg.Server.TestUI.Commons;
using OpenQA.Selenium.Remote;
using Xunit;

namespace nscreg.Server.TestUI.Roles
{
    [TestCaseOrderer("nscreg.Server.TestUI.Commons.PriorityOrderer", "nscreg.Server.TestUI")]
    public class RolesTest : IDisposable
    {
        private readonly RemoteWebDriver _driver;
        private const string RoleNameField = "TestRole";
        private const string EditedTag = "Edited";
        private const string DescriptionField = "Test role";

        public RolesTest()
        {
            _driver = Setup.CreateWebDriver();
        }

        public void Dispose()
        {
            _driver.Quit();
        }

        [Fact, Order(0)]
        public void AddRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.AddRoleAct(RoleNameField, DescriptionField);

            Assert.True(resultRole.AddRolePage(RoleNameField).Contains(RoleNameField));
        }

        [Fact, Order(1)]
        public void EditRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.EditRoleAct(EditedTag, "Edited by Selenium test framework at " + DateTime.Now);

            Assert.True(resultRole.EditRolePage(RoleNameField + EditedTag).Contains(RoleNameField + EditedTag));
        }

        [Fact, Order(2)]
        public void DeleteRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.DeleteRoleAct(RoleNameField + EditedTag);

            Assert.False(resultRole.DeleteRolePage(RoleNameField + EditedTag).Contains(RoleNameField + EditedTag));
        }

        [Fact, Order(3)]
        public void UsersInRole()
        {
            const string userName = "Admin user";
            const string userRole = "System Administrator";
            var home = new RolePage(_driver);

            var resultRole = home.DisplayUserAct(userRole);

            Assert.True(resultRole.DisplayRolePage(userName).Equals(userName));
        }
    }
}