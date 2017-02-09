using System;
using System.Collections;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;
using static nscreg.Server.TestUI.MenuMap;

namespace nscreg.Server.TestUI
{
    public static class CommonScenarios
    {
        public static void SignInAsAdmin(RemoteWebDriver driver, MenuMap map)
        {
            SignIn(driver, "admin", "123qwe", map);
        }

        // ReSharper disable once MemberCanBePrivate.Global
        public static void SignIn(RemoteWebDriver driver, string login, string password, MenuMap map)
        {
            driver.FindElement(By.Name("login")).SendKeys(login);
            driver.FindElement(By.Name("password")).SendKeys(password);
            driver.FindElement(By.XPath("//input[contains(@class, 'ui button middle fluid blue')]")).Click();
            switch (map)
            {
                case MenuMap.Users:
                    driver.FindElement(By.XPath("//a[contains(@class, 'item')][2]")).Click();
                    break;
                case MenuMap.Roles:
                    driver.FindElement(By.XPath("//a[contains(@class, 'item')][3]")).Click();
                    break;
                case MenuMap.StatUnits:
                    driver.FindElement(By.XPath("//a[contains(@class, 'item')][4]")).Click();
                    break;
                case None:
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(map), map, null);
            }
        }

        public static bool CheckLoadingNotification(RemoteWebDriver driver, string message)
        {
            throw new System.NotImplementedException();
        }
    }
}
