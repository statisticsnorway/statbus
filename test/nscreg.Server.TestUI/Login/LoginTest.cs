using System;
using OpenQA.Selenium;
using Xunit;
using static nscreg.Server.TestUI.CommonScenarios;

namespace nscreg.Server.TestUI.Login
{
    public class LoginTest : SeleniumTestBase
    {
        [Fact]
        private void LoginFormDisplayed()
        {
            Driver.Navigate();

            var allInputsRendered = Driver.FindElement(By.Name("login")) != null
                                    && Driver.FindElement(By.Name("password")) != null
                                    && Driver.FindElement(By.Id("rememberMeToggle")) != null;

            Assert.True(allInputsRendered);
        }

        [Fact]
        private void LogInAsAdmin()
        {
            Driver.Navigate();

            SignInAsAdminAndNavigate(Driver, MenuMap.None);

            Assert.Contains("admin", Driver.FindElement(By.XPath("//div[text()='admin']")).Text);
        }

        [Fact]
        private void LogOut()
        {
            Driver.Navigate();
            SignInAsAdminAndNavigate(Driver, MenuMap.None);
            Driver.FindElement(By.XPath("//div[text()='admin']")).Click();
            Driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromMilliseconds(2000);
            Driver.FindElement(By.LinkText("Logout")).Click();
            Driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromMilliseconds(2000);

            Assert.True(Driver.FindElement(By.Name("login")) != null
                        && Driver.FindElement(By.Name("password")) != null
                        && Driver.FindElement(By.Id("rememberMeToggle")) != null);
        }
    }
}
