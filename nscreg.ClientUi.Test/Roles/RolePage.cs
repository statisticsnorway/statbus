using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using UITest;
using NUnit.Framework;
using OpenQA.Selenium.Support.PageObjects;
using OpenQA.Selenium.Support.UI;

namespace UITest.Roles 
{

    public class RolePage
    {
        private IWebDriver _driver;

        public RolePage(ChromeDriver driver)
        {
            this._driver = driver;
            _driver.Navigate().GoToUrl("http://localhost:3000/");
            //_driver.Manage().Window.Maximize();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
        }


        public ResultRolePage AddRoleAct(string _roleNameField, string _descriptionField, string _standardDataAccessField, string _accessToSystemFunctionsField)
        {
            StepsToLogin();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(2));
            _driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();

            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][1]/div[contains(@class, 'ui input')]/input")).SendKeys(_roleNameField);
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][2]/div[contains(@class, 'ui input')]/input")).SendKeys(_descriptionField);

            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][3]/div[contains(@class, 'ui multiple search selection dropdown')]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'menu transition visible')]/div[contains(@class, 'selected item')]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][2]/div[contains(@class, 'ui input')]/input")).Click();

            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][4]/div[contains(@class, 'ui multiple search selection dropdown')]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'menu transition visible')]/div[contains(@class, 'item')][3]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][2]/div[contains(@class, 'ui input')]/input")).Click();
            _driver.FindElement(By.XPath("//button")).Click();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(9));
            return new ResultRolePage(_driver);
        }

        public ResultRolePage EditRoleAct(string _roleNameField, string _descriptionField)
        {
            StepsToLogin();
            _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/div[contains(@class, 'ui input')]/input")).Clear();
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/div[contains(@class, 'ui input')]/input")).SendKeys(_roleNameField);

            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/div[contains(@class, 'ui input')]/input")).Clear();
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/div[contains(@class, 'ui input')]/input")).SendKeys(_descriptionField);

            /*_driver.FindElement(By.XPath("//div[contains(@class, 'required field')][3]/div[contains(@class, 'ui multiple search selection dropdown')]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'menu transition visible')]/div[contains(@class, 'selected item')]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][2]/div[contains(@class, 'ui input')]/input")).Click();

            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][4]/div[contains(@class, 'ui multiple search selection dropdown')]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'menu transition visible')]/div[contains(@class, 'item')][3]")).Click();
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][2]/div[contains(@class, 'ui input')]/input")).Click();*/

            _driver.FindElement(By.XPath("//button")).Click();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(2));
            return new ResultRolePage(_driver);
        }


        public ResultRolePage DeleteRoleAct()
        {
            StepsToLogin();
            
            _driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Click();
            //CheckAlert();
            System.Threading.Thread.Sleep(2000);
            //var wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(5));
            //IAlert alert = wait.Until(drv => AlertIsPresent(drv));
            //alert.Accept();

            //_driver.SwitchTo().Alert().Accept();
             IAlert al = _driver.SwitchTo().Alert();
             al.Accept();
            return new ResultRolePage(_driver);
        }

        public ResultRolePage DisplayUserAct()
        {
            StepsToLogin();
            _driver.FindElement(By.XPath("//button[contains(@class, 'ui teal button')]")).Click();
            System.Threading.Thread.Sleep(2000);
            return new ResultRolePage(_driver);
        }

        public void StepsToLogin(string loginField = "admin", string passwordField = "123qwe")
        {
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/input")).SendKeys(loginField);
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/input")).SendKeys(passwordField);
            _driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();

            _driver.FindElement(By.XPath("//a[contains(@class, 'item')][3]")).Click();
        }

        private IAlert AlertIsPresent(IWebDriver drv)
        {
            try
            {
                // Attempt to switch to an alert
                return drv.SwitchTo().Alert();
            }
            catch (OpenQA.Selenium.NoAlertPresentException)
            {
                // We ignore this execption, as it means there is no alert present...yet.
                return null;
            }

            // Other exceptions will be ignored and up the stack
        }

        public void CheckAlert()
        {
            try
            {
                WebDriverWait wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(5));
                wait.Until(ExpectedConditions.AlertIsPresent());
                IAlert alert = _driver.SwitchTo().Alert();
                alert.Accept();
            }
            catch (Exception e)
            {
                //exception handling
            }
        }
    }
}
