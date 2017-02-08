using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI
{
    public static class CommonScenarios
    {
        public static void SignInAsAdmin(RemoteWebDriver driver)
        {
            SignIn(driver, "admin", "123qwe");
        }

        // ReSharper disable once MemberCanBePrivate.Global
        public static void SignIn(RemoteWebDriver driver, string login, string password)
        {
            driver.FindElement(By.XPath("//div[contains(@class, 'field')][1]/input")).SendKeys(login);
            driver.FindElement(By.XPath("//div[contains(@class, 'field')][2]/input")).SendKeys(password);
            driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();
            driver.FindElement(By.XPath("//a[contains(@class, 'item')][4]")).Click();
        }

        public static bool CheckLoadingNotification(RemoteWebDriver driver, string message)
        {
            throw new System.NotImplementedException();
        }
    }
}
