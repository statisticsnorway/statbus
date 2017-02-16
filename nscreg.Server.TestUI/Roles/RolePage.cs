using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;
using static nscreg.Server.TestUI.CommonScenarios;

namespace nscreg.Server.TestUI.Roles
{
    public class RolePage
    {
        private readonly RemoteWebDriver _driver;

        public RolePage(RemoteWebDriver driver)
        {
            _driver = driver;
            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
        }

        #region CreateRole

        public RolePageResult AddRoleAct(string roleNameField, string descriptionField)
        {
            SignInAsAdmin(_driver, MenuMap.Roles);
            _driver
                .Manage()
                .Timeouts()
                .ImplicitlyWait(TimeSpan.FromSeconds(2));

            _driver
                .FindElement(By.CssSelector("a[href='/roles/create']"))
                .Click();

            _driver
                .FindElement(
                    By.Name("name"))
                .SendKeys(roleNameField);

            _driver
                .FindElement(
                    By.CssSelector("input[name='description']"))
                .SendKeys(descriptionField);

            _driver
                .FindElement(
                    By.XPath(
                        "//div[text()='Select or search standard data access']"))
                .Click();

            _driver
                .FindElement(
                    By.XPath("//div[text()='RegId']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div[text()='Name']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div[text()='Address']"))
                .Click();

            _driver
                .FindElement(
                    By.XPath(
                        "//label[text()='Standard data access']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath(
                        "//div[text()='Select or search system functions']"))
                .Click();

            _driver
                .FindElement(
                    By.XPath("//div[text()='AccountView']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div[text()='UserView']"))
                .Click();
            _driver
                .FindElement(
                    By.XPath("//div[text()='UserListView']"))
                .Click();

            _driver
                .FindElement(
                    By.XPath(
                        "//label[text()='Access to system functions']"))
                .Submit();

            _driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(9));

            return new RolePageResult(_driver);
        }

        #endregion

        #region EditRole

        public RolePageResult EditRoleAct(string roleNameField, string descriptionField)
        {
            SignInAsAdmin(_driver, MenuMap.Roles);
            _driver
                .FindElement(By.XPath("//a[text()='TestRole']"))
                .Click();

            _driver
                .FindElement(By.Name("name"))
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
            SignInAsAdmin(_driver, MenuMap.Roles);

            _driver.FindElement(
                    By.XPath($"//a[text()='{name}']/../../td/div/button[@class='ui red icon button']"))
                .Click();
            System.Threading.Thread.Sleep(2000);
            var alert = _driver.SwitchTo().Alert();
            alert.Accept();
            return new RolePageResult(_driver);
        }

        #endregion

        public RolePageResult DisplayUserAct(string name)
        {
            SignInAsAdmin(_driver, MenuMap.Roles);
            _driver.FindElement(
                    By.XPath($"//a[text()='{name}']/../../td/button[@class='ui teal button']"))
                .Click();
            System.Threading.Thread.Sleep(2000);
            return new RolePageResult(_driver);
        }
    }
}