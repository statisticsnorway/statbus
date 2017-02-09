using System;
using OpenQA.Selenium;
using nscreg.Server.TestUI.Commons;
using Xunit;

namespace nscreg.Server.TestUI.Roles
{
    [TestCaseOrderer("nscreg.Server.TestUI.Commons.PriorityOrderer", "nscreg.Server.TestUI")]
    public class RolesTest : IDisposable
    {
        private readonly IWebDriver _driver;
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

        [Fact, TestPriority(0)]
        public void AddRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.AddRoleAct(RoleNameField, DescriptionField);

            Assert.True(resultRole.AddRolePage(RoleNameField).Contains(RoleNameField));
        }

        [Fact, TestPriority(1)]
        public void EditRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.EditRoleAct(EditedTag, "Edited by Selenium test framework at " + DateTime.Now);

            Assert.True(resultRole.EditRolePage(RoleNameField + EditedTag).Contains(RoleNameField + EditedTag));
        }

        [Fact, TestPriority(2)]
        public void DeleteRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.DeleteRoleAct(RoleNameField + EditedTag);

            Assert.False(resultRole.DeleteRolePage(RoleNameField + EditedTag).Contains(RoleNameField + EditedTag));
        }

        [Fact]
        public void UsersInRole()
        {
            var home = new RolePage(_driver);

            var resultRole = home.DisplayUserAct();

            Assert.True(resultRole.DisplayRolePage());
        }
    }
}