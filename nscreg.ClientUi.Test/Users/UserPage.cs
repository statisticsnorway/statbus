using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using UITest;
using NUnit.Framework;
using OpenQA.Selenium.Support.PageObjects;
using OpenQA.Selenium.Support.UI;
using UITest.Users;

namespace UITest.Roles 
{
    public class UserPage
    {
        private IWebDriver _driver;

        public UserPage(ChromeDriver driver)
        {
            this._driver = driver;
            _driver.Navigate().GoToUrl("http://localhost:3000/");
            //_driver.Manage().Window.Maximize();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
        }


        public ResultUserPage AddUserAct(string userName, string userLogin, string userPassword, string confirmPassword, string userEmail, string userPhone, string assignedRoles, string userStatus, string dataAccess, string description)
        {
            StepsToLogin();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(2));
            _driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();

            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][1]/div[contains(@class, 'ui input')]/input")).SendKeys(userName);
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][2]/div[contains(@class, 'ui input')]/input")).SendKeys(userLogin);
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][3]/div[contains(@class, 'ui input')]/input")).SendKeys(userPassword);
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][4]/div[contains(@class, 'ui input')]/input")).SendKeys(confirmPassword);
            _driver.FindElement(By.XPath("//div[contains(@class, 'required field')][5]/div[contains(@class, 'ui input')]/input")).SendKeys(userEmail);
            _driver.FindElement(By.Name("phone")).SendKeys(userPhone);

            _driver.FindElement(By.XPath("//button")).Click();
            return new ResultUserPage(_driver);
        }

        public ResultUserPage EditUserAct(string userNameField, string descriptionField)
        {
            StepsToLogin();
            _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Click();

            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/div[contains(@class, 'ui input')]/input")).Clear();
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/div[contains(@class, 'ui input')]/input")).SendKeys(userNameField+"2");

            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][10]/div[contains(@class, 'ui input')]/input")).Clear();
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][10]/div[contains(@class, 'ui input')]/input")).SendKeys(descriptionField);

            _driver.FindElement(By.XPath("//button")).Click();
            return new ResultUserPage(_driver);
        }


        public ResultUserPage DeleteUserAct()
        {
            StepsToLogin();
            
            _driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Click();
            System.Threading.Thread.Sleep(2000);
            IAlert al = _driver.SwitchTo().Alert();
            al.Accept();
            return new ResultUserPage(_driver);
        }



        public void StepsToLogin(string loginField = "admin", string passwordField = "123qwe")
        {
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/input")).SendKeys(loginField);
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/input")).SendKeys(passwordField);
            _driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();

            _driver.FindElement(By.XPath("//div[contains(@class, 'ui right aligned container')]/a[contains(@class, 'item')][2]")).Click();
        }
    }
}
