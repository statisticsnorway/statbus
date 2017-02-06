using OpenQA.Selenium;
using Xunit;

namespace nscreg.Server.TestUI
{
    public class SmokeTest
    {
        [Fact]
        private void LoginFormDisplayed()
        {
            var driver = Setup.CreateWebDriver();
            driver.Navigate();

            var allInputsRendered = driver.FindElement(By.Name("login")) != null
                                    && driver.FindElement(By.Name("password")) != null
                                    && driver.FindElement(By.Id("rememberMeToggle")) != null;

            Assert.True(allInputsRendered);
            driver.Quit();
        }
    }
}
