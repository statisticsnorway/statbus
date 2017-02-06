using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;

namespace UITest
{
    [TestClass]
    public class HomePage
    {
        private IWebDriver _driver;

        public HomePage(ChromeDriver driver)
        {
            this._driver = driver;
            _driver.Navigate().GoToUrl("http://localhost:3000/");
            //_driver.Manage().Window.Maximize();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));

        }

        public void StepsToLogin(string loginField = "admin", string passwordField = "123qwe")
        {
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/input")).SendKeys(loginField);
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/input")).SendKeys(passwordField);
            _driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();
        }

        public ResultRolePage LoginAct(string loginField, string passwordField)
        {
             StepsToLogin(loginField, passwordField);
             return new ResultRolePage(_driver);
        }

    }
}
