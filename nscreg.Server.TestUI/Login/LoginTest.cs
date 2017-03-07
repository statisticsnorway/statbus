using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Interactions;
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

            Assert.True(Driver
                .FindElement(By.XPath("//div[contains(@class, 'text')]"))
                .Text
                .Contains("admin"));
        }

        [Fact]
        private void LogOut()
        {
            Driver.Navigate();
            SignInAsAdminAndNavigate(Driver, MenuMap.None);

            var accDiv = Driver.FindElement(By.XPath("//div[text()='admin']"));
            new Actions(Driver).MoveToElement(accDiv).Perform();
            Driver.FindElement(By.LinkText("Logout")).Click();
            Driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromMilliseconds(2000));

            Assert.True(Driver.FindElement(By.Name("login")) != null
                        && Driver.FindElement(By.Name("password")) != null
                        && Driver.FindElement(By.Id("rememberMeToggle")) != null);
        }
    }
}
