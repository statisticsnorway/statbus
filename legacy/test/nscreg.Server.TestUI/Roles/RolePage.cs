using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Interactions;
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
                .ImplicitWait = TimeSpan.FromSeconds(2);

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
                        "//div[text()='Legal unit']"))
                .Click();

            driver
                .FindElement(
                    By.XPath("//label[text()='Address']"))
                .Click();
            driver
                .FindElement(
                    By.XPath("//label[text()='ActualAddress']"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//div[text()='Legal unit']"))
                .Click();

            new Actions(driver).MoveToElement(driver.FindElement(By.LinkText("About"))).Perform();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Account']/../td[2]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Account']/../td[4]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Roles']/../td[2]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Roles']/../td[3]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Roles']/../td[4]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Roles']/../td[5]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Users']/../td[3]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Stat units']/../td[2]/div"))
                .Click();


            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Stat units']/../td[3]/div"))
                .Click();


            driver
                .FindElement(
                    By.XPath(
                        "//td[text()='Stat units']/../td[4]/div"))
                .Click();

            driver
                .FindElement(
                    By.XPath(
                        "//button[text()='Submit']"))
                .Click();

            driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromSeconds(9);
        }

        public static void Edit(RemoteWebDriver driver, string roleNameField, string editTag,string descriptionField)
        {
            driver
                .FindElement(By.XPath($"//a[text()='{roleNameField}']"))
                .Click();

            driver
                .FindElement(By.Name("name"))
                .SendKeys(editTag);

            driver
                .FindElement(By.CssSelector("input[name='description']"))
                .Clear();

            driver
                .FindElement(By.CssSelector("input[name='description']"))
                .SendKeys(descriptionField);

            driver
                .FindElement(By.XPath("//button[text()='Submit']"))
                .Click();

            driver
                .Manage()
                .Timeouts()
                .ImplicitWait = TimeSpan.FromSeconds(2);
        }

        public static void Delete(RemoteWebDriver driver, string name)
        {
            driver.FindElement(
                    By.XPath($"//a[text()='{name}']/../../td/div/button[@class='ui red icon button']"))
                .Click();
            driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromSeconds(5);
            driver.SwitchTo().Alert().Accept();
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

        public static bool IsEdited(RemoteWebDriver driver, string roleNameField, string editTag)
            => driver.FindElement(By.XPath($"//a[text()='{roleNameField + editTag}']")).Displayed;

        public static bool IsDeleted(RemoteWebDriver driver, string roleName, string editTag)
            => !driver.FindElement(By.XPath($"//a[text()='{roleName + editTag}']")).Displayed;

        public static bool IsUsersDisplayed(RemoteWebDriver driver, string name)
            => driver.FindElement(By.XPath($"//a[text()='{name}']")).Displayed;

        #endregion
    }
}
