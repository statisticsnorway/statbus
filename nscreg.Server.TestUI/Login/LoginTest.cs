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

            SignInAsAdmin(Driver);

            Assert.True(Driver
                .FindElement(By.XPath("//div[contains(@class, 'text')]"))
                .Text
                .Contains("admin"));
        }

        [Fact]
        private void LogOut()
        {
            Driver.Navigate();
            SignInAsAdmin(Driver);

            var accDiv = Driver.FindElement(By.XPath("//*[@id=\"root\"]/div/header/div/div/div/div[2]/div[1]"));
            new Actions(Driver).MoveToElement(accDiv).Perform();
            Driver.FindElement(By.XPath("//*[@id=\"root\"]/div/header/div/div/div/div[2]/div[2]/a[2]")).Click();

            Assert.True(Driver.FindElement(By.Name("login")) != null
                        && Driver.FindElement(By.Name("password")) != null
                        && Driver.FindElement(By.Id("rememberMeToggle")) != null);
        }
    }
}
