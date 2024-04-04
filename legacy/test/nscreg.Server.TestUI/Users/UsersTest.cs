using System;
using nscreg.Server.TestUI.Commons;
using OpenQA.Selenium;
using Xunit;
using static nscreg.Server.TestUI.CommonScenarios;
using static nscreg.Server.TestUI.Users.UserPage;

namespace nscreg.Server.TestUI.Users
{
    public class UsersTest : SeleniumTestBase
    {
        private const string UserName = "TestName";
        private const string EditTag = "Edited";
        private const string UserLogin = "TestLogin";
        private const string UserPassword = "123456789";
        private const string ConfirmPassword = "123456789";
        private const string UserEmail = "test@gmail.com";
        private const string UserPhone = "555123456";

        [Fact, Order(0)]
        private void AddUser()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Users);

            Add(Driver,
                UserName, UserLogin, UserPassword,
                ConfirmPassword, UserEmail, UserPhone);

            Assert.True(IsExists(Driver, UserName));
        }

        [Fact, Order(1)]
        private void EditUser()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Users);

            Edit(Driver, UserName, EditTag);
            Driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromSeconds(5);

            Assert.True(IsExists(Driver, UserName + EditTag));
        }

        [Fact, Order(2)]
        private void DeleteUser()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.Users);
            Delete(Driver);
            Assert.Throws<NoSuchElementException>(() => IsDeleted(Driver));
        }
    }
}
