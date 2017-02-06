using System;
using NUnit.Framework;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;


namespace UITest
{
    [TestFixture]
    public class Login
    {
        private ChromeDriver _driver;
        private string _loginField = "admin";
        private string _passwordField = "123qwe";

        [SetUp]
        public void Setup()
        {
            _driver= new ChromeDriver();
        }

        
        //[Test]
        public void EnterTheSystem()
        {
            HomePage home = new HomePage(_driver);
           
            ResultRolePage resultRole = home.LoginAct(_loginField, _passwordField);

            Assert.IsTrue(resultRole.MainPage().Contains(_loginField));
        }

        [TearDown]
        public void TearDown()
        {
            _driver.Quit();
        }

    }
}
