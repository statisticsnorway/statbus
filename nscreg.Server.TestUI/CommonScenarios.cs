using System;
using System.Collections.Generic;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI
{
    public static class CommonScenarios
    {
        private static readonly Dictionary<MenuMap, string> MenuMapDictionary;

        static CommonScenarios()
        {
            MenuMapDictionary = new Dictionary<MenuMap, string>
            {
                [MenuMap.Users] = "a[href='/users']",
                [MenuMap.Roles] = "a[href='/roles']",
                [MenuMap.StatUnits] = "a[href='/statunits']",
                [MenuMap.None] = "a[href='/']"
            };

        }
        public static void SignInAsAdmin(RemoteWebDriver driver, MenuMap map)
        {
            SignIn(driver, "admin", "123qwe", map);
        }

        // ReSharper disable once MemberCanBePrivate.Global
        public static void SignIn(RemoteWebDriver driver, string login, string password, MenuMap map)
        {
            driver.FindElement(By.Name("login")).SendKeys(login);
            driver.FindElement(By.Name("password")).SendKeys(password);
            driver.FindElement(By.CssSelector("input[type='submit']")).Submit();
            driver.FindElement(By.CssSelector(MenuMapDictionary[map])).Click();
        }

        public static bool CheckLoadingNotification(RemoteWebDriver driver, string message)
        {
            throw new NotImplementedException();
        }
    }
}