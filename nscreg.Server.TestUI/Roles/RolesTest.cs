using System;
using nscreg.Server.TestUI.Commons;
using OpenQA.Selenium;
using Xunit;
using static nscreg.Server.TestUI.CommonScenarios;
using static nscreg.Server.TestUI.Roles.RolePage;

namespace nscreg.Server.TestUI.Roles
{
    public class RolesTest : SeleniumTestBase
    {
        private const string RoleNameField = "TestRole";
        private const string EditedTag = "Edited";
        private const string DescriptionField = "Test role";
        private const string AdminName = "Admin user";
        private const string AdminRole = "System Administrator";

        [Fact, Order(0)]
        public void AddRole()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Roles);

            Add(Driver, RoleNameField, DescriptionField);

            Assert.True(IsAdded(Driver, RoleNameField));
        }

        [Fact, Order(1)]
        public void EditRole()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Roles);

            Edit(Driver, EditedTag, "Edited by Selenium test framework at " + DateTime.Now);

            Assert.True(IsEdited(Driver, RoleNameField, EditedTag));
        }

        [Fact, Order(2)]
        public void DeleteRole()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Roles);
            Delete(Driver, RoleNameField + EditedTag);
            Assert.Throws<NoSuchElementException>(() => IsDeleted(Driver, RoleNameField, EditedTag));
        }

        [Fact, Order(3)]
        public void UsersInRole()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Roles);

            DisplayUsers(Driver, AdminRole);

            Assert.True(IsUsersDisplayed(Driver, AdminName));
        }
    }
}
