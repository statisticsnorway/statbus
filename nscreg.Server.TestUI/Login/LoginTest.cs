using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;
using Xunit;

namespace nscreg.Server.TestUI.Login
{
    public class LoginTest : IDisposable
    {
        private readonly RemoteWebDriver _driver;

        public LoginTest()
        {
            _driver = Setup.CreateWebDriver();
        }

        public void Dispose()
        {
            _driver.Quit();
        }

        [Fact]
        private void LoginFormDisplayed()
        {
            _driver.Navigate();

            var allInputsRendered = _driver.FindElement(By.Name("login")) != null
                                    && _driver.FindElement(By.Name("password")) != null
                                    && _driver.FindElement(By.Id("rememberMeToggle")) != null;

            Assert.True(allInputsRendered);
        }

        [Fact]
        private void EnterTheSystem()
        {
            _driver.Navigate();
            var page = new HomePage(_driver);

            page.LoginAct("admin", "123qwe");

            Assert.True(_driver
                .FindElement(By.XPath("//div[contains(@class, 'text')]"))
                .Text
                .Contains("admin"));
        }
    }
}
