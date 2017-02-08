using System;
using nscreg.Server.TestUI.Commons;
using OpenQA.Selenium.Remote;
using Xunit;

namespace nscreg.Server.TestUI.Users
{
    [TestCaseOrderer("nscreg.Server.TestUI.Commons.PriorityOrderer", "nscreg.Server.TestUI")]
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

        [Fact, TestPriority(0)]
        private void AddUser()
        {
            var page = new UserPage(_driver);

            UserPageResult resultUser = page.AddUserAct(
                _userName, _userLogin, _userPassword,
                _confirmPassword, _userEmail, _userPhone);

            Assert.True(resultUser.AddUserPage().Contains(_userName));
        }

        [Fact, TestPriority(1)]
        private void EditUser()
        {
            var page = new UserPage(_driver);

            UserPageResult result = page.EditUserAct(_userName, _description);

            Assert.True(result.EditUserPage().Contains(_userName));
        }

        [Fact, TestPriority(2)]
        private void DeleteUser()
        {
            var page = new UserPage(_driver);

            UserPageResult result = page.DeleteUserAct();

            Assert.NotEqual(result.DeleteUserPage(), true);
        }
    }
}
