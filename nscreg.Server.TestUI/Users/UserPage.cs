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
            driver.Manage().Timeouts().ImplicitlyWait(TimeSpan.FromSeconds(1));
            driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();

            driver.FindElement(By.Name("name")).SendKeys(userName);
            driver.FindElement(By.Name("login")).SendKeys(userLogin);
            driver.FindElement(By.Name("password")).SendKeys(userPassword);
            driver.FindElement(By.Name("confirmPassword")).SendKeys(confirmPassword);
            driver.FindElement(By.Name("email")).SendKeys(userEmail);
            driver.FindElement(By.Name("phone")).SendKeys(userPhone);

            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void Edit(RemoteWebDriver driver, string userNameField, string descriptionField)
        {
            driver.FindElement(By.XPath("//tbody/tr/td/a[contains(text(),'TestName')]")).Click();

            driver.FindElement(By.Name("name")).Clear();
            driver.FindElement(By.Name("name")).SendKeys(userNameField + "2");

            driver.FindElement(By.XPath("//div[contains(@class, 'field')][10]/div[contains(@class, 'ui input')]/input"))
                .Clear();
            driver.FindElement(By.XPath("//div[contains(@class, 'field')][10]/div[contains(@class, 'ui input')]/input"))
                .SendKeys(descriptionField);

            driver.FindElement(By.XPath("//button")).Click();
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

        public static bool IsAdded(RemoteWebDriver driver, string userName) => driver
            .FindElement(By.XPath($"//tbody/tr/td/a[text()='{userName}']"))
            .Displayed;

        public static bool IsEdited(RemoteWebDriver driver, string userName) => driver
            .FindElement(By.XPath($"//tbody/tr/td/a[contains(text(),'{userName}')]"))
            .Displayed;


        public static bool IsDeleted(RemoteWebDriver driver) => !driver
            .FindElement(By.XPath("//tbody[2]/tr/td[1]/a"))
            .Displayed;

        #endregion
    }
}
