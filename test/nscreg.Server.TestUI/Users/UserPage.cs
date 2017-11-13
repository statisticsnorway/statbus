using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI.Users
{
    public static class UserPage
    {
        #region ACTIONS

        public static void Add(RemoteWebDriver driver,
            string userName, string userLogin,
            string userPassword, string confirmPassword,
            string userEmail, string userPhone)
        {
            driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromSeconds(1);
            driver.FindElement(By.LinkText("Create user")).Click();

            driver.FindElement(By.Name("name")).SendKeys(userName);
            driver.FindElement(By.Name("login")).SendKeys(userLogin);
            driver.FindElement(By.Name("password")).SendKeys(userPassword);
            driver.FindElement(By.Name("confirmPassword")).SendKeys(confirmPassword);
            driver.FindElement(By.Name("email")).SendKeys(userEmail);
            driver.FindElement(By.Name("phone")).SendKeys(userPhone);

            driver.FindElement(By.XPath("//button[text()='Submit']")).Click();
        }

        public static void Edit(RemoteWebDriver driver, string userNameField, string editTag)
        {
            driver.FindElement(By.LinkText(userNameField)).Click();

            driver.FindElement(By.Name("name")).SendKeys(editTag);
            driver.FindElement(By.XPath("//button[text()='Submit']")).Click();
        }

        public static void Delete(RemoteWebDriver driver)
        {
            driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Click();
            System.Threading.Thread.Sleep(2000);
            var al = driver.SwitchTo().Alert();
            al.Accept();
        }

        #endregion

        #region ASSERTIONS

        public static bool IsExists(RemoteWebDriver driver, string userName) => driver
            .FindElement(By.LinkText(userName))
            .Displayed;

        public static bool IsDeleted(RemoteWebDriver driver) => !driver
            .FindElement(By.XPath("//tbody[2]/tr/td[1]/a"))
            .Displayed;

        #endregion
    }
}
