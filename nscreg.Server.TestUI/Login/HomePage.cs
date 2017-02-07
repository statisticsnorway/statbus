using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI.Login
{
    public class HomePage
    {
        private readonly RemoteWebDriver _driver;

        public HomePage(RemoteWebDriver driver)
        {
            _driver = driver;
            //_driver.Manage().Window.Maximize();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
        }

        public void LoginAct(string loginField, string passwordField)
        {
            StepsToLogin(loginField, passwordField);
        }

        private void StepsToLogin(string loginField, string passwordField)
        {
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/input")).SendKeys(loginField);
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/input")).SendKeys(passwordField);
            _driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();
        }
    }
}
