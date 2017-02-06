using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using NUnit.Framework;
using NUnit.Framework.Internal;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Support.UI;
using UITest.Users;
using Assert = NUnit.Framework.Assert;


namespace UITest.Roles
{
    [TestFixture]
    public class User
    {
        ChromeDriver _driver;
        private string _userName = "TestName";
        private string _userLogin = "TestLogin";
        private string _userPassword = "123456789";
        private string _confirmPassword = "123456789";
        private string _userEmail = "test@gmail.com";
        private string _userPhone = "555123456";
        private string _assignedRoles = "System Administrator";
        private string _userStatus = "Active";
        private string _dataAccess = "RegId";
        private string _description = "Sample text";


        [SetUp]
        public void Setup()
        {
            _driver = new ChromeDriver();
        }


      // [Test]
        public void AddUser()
        {
            UserPage home = new UserPage(_driver);
            ResultUserPage resultUser = home.AddUserAct(
                _userName, _userLogin, _userPassword,
                _confirmPassword, _userEmail, _userPhone, 
                _assignedRoles, _userStatus, _dataAccess, _description);
            Assert.IsTrue(resultUser.AddUserPage().Contains(_userName));
        }

        // [Test]
        public void EditUser()
        {
            UserPage home = new UserPage(_driver);
            ResultUserPage result = home.EditUserAct(_userName,_description);
            Assert.IsTrue(result.EditUserPage().Contains(_userName));
        }

        [Test]
        public void DeleteUser()
        {
            UserPage home = new UserPage(_driver);
            ResultUserPage result = home.DeleteUserAct();
            Assert.AreNotEqual(result.DeleteUserPage(), true);
        }

        [TearDown]
        public void TearDown()
        {
           _driver.Quit();
        }

    }
}
