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

            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/input")).SendKeys("admin");
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/input")).SendKeys("123qwe");
            _driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();

            Assert.True(_driver
                .FindElement(By.XPath("//div[contains(@class, 'text')]"))
                .Text
                .Contains("admin"));
        }
    }
}
