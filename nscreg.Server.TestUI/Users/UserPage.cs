using System;
using System.Linq;
using OpenQA.Selenium;

namespace nscreg.Server.TestUI.Users
{
    public class UserPage
    {
        private readonly IWebDriver _driver;

        public UserPage(IWebDriver driver)
        {
            _driver = driver;
            //_driver.Manage().Window.Maximize();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
        }

        public UserPageResult AddUserAct(string userName, string userLogin, string userPassword, string confirmPassword,
            string userEmail, string userPhone)
        {
            StepsToLogin();
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(2));
            _driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();

            _driver.FindElement(By.Name("name")).SendKeys(userName);
            _driver.FindElement(By.Name("login")).SendKeys(userLogin);
            _driver.FindElement(By.Name("password")).SendKeys(userPassword);
            _driver.FindElement(By.Name("confirmPassword")).SendKeys(confirmPassword);
            _driver.FindElement(By.Name("email")).SendKeys(userEmail);
            _driver.FindElement(By.Name("phone")).SendKeys(userPhone);

            _driver.FindElement(By.XPath("//button")).Click();
            return new UserPageResult(_driver);
        }

        public UserPageResult EditUserAct(string userNameField, string descriptionField)
        {
            StepsToLogin();
            _driver.FindElement(By.XPath("//tbody/tr/td/a[contains(text(),'TestName')]")).Click();

            _driver.FindElement(By.Name("name")).Clear();
            _driver.FindElement(By.Name("name")).SendKeys(userNameField + "2");

            
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][10]/div[contains(@class, 'ui input')]/input")).Clear();
            _driver.FindElement(By.XPath("//div[contains(@class, 'field')][10]/div[contains(@class, 'ui input')]/input")).SendKeys(descriptionField);

            _driver.FindElement(By.XPath("//button")).Click();
            return new UserPageResult(_driver);
        }


        public UserPageResult DeleteUserAct()
        {
            StepsToLogin();

            _driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Click();
            System.Threading.Thread.Sleep(2000);
            IAlert al = _driver.SwitchTo().Alert();
            al.Accept();
            return new UserPageResult(_driver);
        }


        private void StepsToLogin(string loginField = "admin", string passwordField = "123qwe")
        {
            _driver.FindElement(By.Name("login")).SendKeys(loginField);
            _driver.FindElement(By.Name("password")).SendKeys(passwordField);
            _driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();

            _driver.FindElement(
                    By.XPath("//div[contains(@class, 'ui right aligned container')]/a[contains(@class, 'item')][2]"))
                .Click();
        }
    }
}
