using System;
using NUnit.Framework;
using NUnit.Framework.Internal;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Support.UI;
using Assert = NUnit.Framework.Assert;


namespace UITest.Roles
{
    [TestFixture]
    public class Role
    {
        ChromeDriver _driver;
        private string _roleNameField = "Manager";
        private string _descriptionField = "Manager role";
        private string _standardDataAccessField = "RegId";
        private string _accessToSystemFunctionsField = "UserCreate";

        [SetUp]
        public void Setup()
        {
            _driver = new ChromeDriver();
        }


         //[Test]
        public void AddRole()
        {
            RolePage home = new RolePage(_driver);
            ResultRolePage resultRole = home.AddRoleAct(_roleNameField, _descriptionField, _standardDataAccessField, _accessToSystemFunctionsField);
            Assert.IsTrue(resultRole.AddRolePage().Contains(_roleNameField));
        }

        //[Test]
        public void EditRole()
        {
            RolePage home = new RolePage(_driver);
            ResultRolePage resultRole = home.EditRoleAct(_roleNameField, _descriptionField);
            Assert.IsTrue(resultRole.EditRolePage().Contains(_roleNameField));
        }

        //[Test]
        public void DeleteRole()
        {
            RolePage home = new RolePage(_driver);
            ResultRolePage resultRole = home.DeleteRoleAct();
            Assert.IsFalse(resultRole.DeleteRolePage().Contains(_roleNameField));
        }

        //[Test]
        public void UsersInRole()
        {
            RolePage home = new RolePage(_driver);
            ResultRolePage resultRole = home.DisplayUserAct();
            Assert.IsTrue(resultRole.DisplayRolePage());
        }

        [TearDown]
        public void TearDown()
        {
           _driver.Quit();
        }

    }
}
