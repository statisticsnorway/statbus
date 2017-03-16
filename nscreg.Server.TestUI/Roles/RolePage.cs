using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI.Roles
{
    public static class RolePage
    {
        #region ACTIONS

        public static void Add(RemoteWebDriver driver, string roleNameField, string descriptionField)
        {
            driver
                .Manage()
                .Timeouts()
                .ImplicitlyWait(TimeSpan.FromSeconds(2));

            driver
                .FindElement(By.CssSelector("a[href='/roles/create']"))
                .Click();

            driver
                .FindElement(
                    By.Name("name"))
                .SendKeys(roleNameField);

            driver
                .FindElement(
                    By.CssSelector("input[name='description']"))
                .SendKeys(descriptionField);

            driver
                .FindElement(
                    By.XPath(
                        "//div[text()='Select or search standard data access']"))
                .Click();

            driver
                .FindElement(
                    By.XPath("//div[text()='Registration id']"))
                .Click();
            driver
                .FindElement(
                    By.XPath("//div[text()='Name']"))
                .Click();
            driver
                .FindElement(
                    By.XPath("//div[text()='Address']"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//label[text()='Standard data access']"))
                .Click();
            driver
                .FindElement(
                    By.XPath(
                        "//div[text()='Select or search system functions']"))
                .Click();

            driver
                .FindElement(
                    By.XPath("//div[text()='AccountView']"))
                .Click();
            driver
                .FindElement(
                    By.XPath("//div[text()='UserView']"))
                .Click();
            driver
                .FindElement(
                    By.XPath("//div[text()='UserView']"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//label[text()='Access to system functions']"))
                .Submit();

            driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(9));
        }

        public static void Edit(RemoteWebDriver driver, string roleNameField, string descriptionField)
        {
            driver
                .FindElement(By.XPath("//a[text()='TestRole']"))
                .Click();

            driver
                .FindElement(By.Name("name"))
                .SendKeys(roleNameField);

            driver
                .FindElement(By.CssSelector("input[name='description']"))
                .Clear();

            driver
                .FindElement(By.CssSelector("input[name='description']"))
                .SendKeys(descriptionField);

            driver
                .FindElement(By.CssSelector("button[type='submit']"))
                .Click();

            driver
                .Manage()
                .Timeouts()
                .ImplicitlyWait(TimeSpan.FromSeconds(2));
        }

        public static void Delete(RemoteWebDriver driver, string name)
        {
            driver.FindElement(
                    By.XPath($"//a[text()='{name}']/../../td/div/button[@class='ui red icon button']"))
                .Click();
            System.Threading.Thread.Sleep(2000);
            var alert = driver.SwitchTo().Alert();
            alert.Accept();
        }

        public static void DisplayUsers(RemoteWebDriver driver, string name)
        {
            driver.FindElement(
                    By.XPath($"//a[text()='{name}']/../../td/button[@class='ui teal button']"))
                .Click();
            System.Threading.Thread.Sleep(2000);
        }

        #endregion

        #region ASSERTIONS

        public static bool IsAdded(RemoteWebDriver driver, string roleName)
            => driver.FindElement(By.XPath($"//a[text()='{roleName}']")).Displayed;

        public static bool IsEdited(RemoteWebDriver driver, string roleNameField, string editedTag)
            => driver.FindElement(By.XPath($"//a[text()='{roleNameField + editedTag}']")).Displayed;

        public static bool IsDeleted(RemoteWebDriver driver, string roleName, string editTag)
            => !driver.FindElement(By.XPath($"//a[text()='{roleName + editTag}']")).Displayed;

        public static bool IsUsersDisplayed(RemoteWebDriver driver, string name)
            => driver.FindElement(By.XPath($"//a[text()='{name}']")).Displayed;

        #endregion
    }
}
