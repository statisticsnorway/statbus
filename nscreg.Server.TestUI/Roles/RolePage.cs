using System;
using OpenQA.Selenium;

namespace nscreg.Server.TestUI.Roles
{
    public class RolePage
    {
        private readonly IWebDriver _driver;

        public RolePage(IWebDriver driver)
        {
            _driver = driver;
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
        }

        #region CreateRole

        public RolePageResult AddRoleAct(string roleNameField, string descriptionField)
        {
            StepsToLogin();

            _driver
                .Manage()
                .Timeouts()
                .ImplicitlyWait(TimeSpan.FromSeconds(2));

            _driver
                .FindElement(By.CssSelector("a[href='/roles/create']"))
                .Click();

            _driver
                .FindElement(
                    By.CssSelector("input[name='name']"))
                .SendKeys(roleNameField);

            _driver
                .FindElement(
                    By.CssSelector("input[name='description']"))
                .SendKeys(descriptionField);

            _driver
                .FindElement(
                    By.XPath(
                        "//div/main/div[2]/div/div/form/div[3]/div"))
                .Click();

            _driver
                .FindElement(
                    By.XPath("//div/div[text()='RegId']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div/div[text()='Name']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div/div[text()='Address']"))
                .Click();

            _driver
                .FindElement(
                    By.XPath(
                        "//div/main/div[2]/div/div/form/h2"))
                .Click();
            _driver
                .FindElement(
                    By.XPath(
                        "//div/main/div[2]/div/div/form/div[4]/div"))
                .Click();

            _driver
                .FindElement(
                    By.XPath("//div/div[text()='AccountView']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div/div[text()='UserView']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div/div[text()='UserListView']"))
                .Click();

            _driver
                .FindElement(
                    By.XPath(
                        "//div/main/div[2]/div/div/form/h2"))
                .Click();


            _driver.FindElement(By.CssSelector("button[type='submit']")).Click();

            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(9));

            return new RolePageResult(_driver);
        }

        #endregion

        #region EditRole

        public RolePageResult EditRoleAct(string roleNameField, string descriptionField)
        {
            StepsToLogin();

            _driver
                .FindElement(By.XPath("//tbody/tr/td/a[text()='TestRole']"))
                .Click();

            _driver
                .FindElement(By.CssSelector("input[name='name']"))
                .SendKeys(roleNameField);

            _driver
                .FindElement(By.CssSelector("input[name='description']"))
                .Clear();

            _driver
                .FindElement(By.CssSelector("input[name='description']"))
                .SendKeys(descriptionField);

            _driver
                .FindElement(By.CssSelector("button[type='submit']"))
                .Click();

            _driver
                .Manage()
                .Timeouts()
                .ImplicitlyWait(TimeSpan.FromSeconds(2));

            return new RolePageResult(_driver);
        }

        #endregion

        #region DeleteRole

        public RolePageResult DeleteRoleAct(string name)
        {
            StepsToLogin();

            _driver.FindElement(
                    By.XPath($"//tbody/tr/td/a[text()='{name}']/../../td/div/button[@class='ui red icon button']"))
                .Click();
            System.Threading.Thread.Sleep(2000);
            var alert = _driver.SwitchTo().Alert();
            alert.Accept();
            return new RolePageResult(_driver);
        }

        #endregion

        public RolePageResult DisplayUserAct()
        {
            StepsToLogin();
            _driver.FindElement(By.XPath("//button[contains(@class, 'ui teal button')]")).Click();
            System.Threading.Thread.Sleep(2000);
            return new RolePageResult(_driver);
        }

        private void StepsToLogin(string loginField = "admin", string passwordField = "123qwe")
        {
            _driver
                .FindElement(By.XPath("//div[contains(@class, 'field')][1]/input"))
                .SendKeys(loginField);

            _driver
                .FindElement(By.XPath("//div[contains(@class, 'field')][2]/input"))
                .SendKeys(passwordField);

            _driver
                .FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]"))
                .Click();

            _driver
                .FindElement(By.XPath("//a[contains(@class, 'item')][3]"))
                .Click();
        }
    }
}