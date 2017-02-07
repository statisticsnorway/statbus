using System;
using OpenQA.Selenium.Remote;
using Xunit;

namespace nscreg.Server.TestUI.Users
{
    public class UsersTest : IDisposable
    {
        private readonly RemoteWebDriver _driver;
        private readonly string _userName = "TestName";
        private readonly string _userLogin = "TestLogin";
        private readonly string _userPassword = "123456789";
        private readonly string _confirmPassword = "123456789";
        private readonly string _userEmail = "test@gmail.com";
        private readonly string _userPhone = "555123456";
        private readonly string _description = "Sample text";

        public UsersTest()
        {
            _driver = Setup.CreateWebDriver();
        }

        public void Dispose()
        {
            _driver.Quit();
        }

        [Fact]
        private void AddUser()
        {
            var page = new UserPage(_driver);

            ResultUserPage resultUser = page.AddUserAct(
                _userName, _userLogin, _userPassword,
                _confirmPassword, _userEmail, _userPhone);

            Assert.True(resultUser.AddUserPage().Contains(_userName));
        }

        [Fact]
        public void EditUser()
        {
            var page = new UserPage(_driver);

            ResultUserPage result = page.EditUserAct(_userName, _description);

            Assert.True(result.EditUserPage().Contains(_userName));
        }

        [Fact]
        public void DeleteUser()
        {
            var page = new UserPage(_driver);

            ResultUserPage result = page.DeleteUserAct();

            Assert.NotEqual(result.DeleteUserPage(), true);
        }
    }
}
