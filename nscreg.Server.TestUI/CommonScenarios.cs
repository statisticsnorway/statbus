using System.Collections.Generic;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI
{
    public static class CommonScenarios
    {
        private static readonly Dictionary<MenuMap, By> ByMenu = new Dictionary<MenuMap, By>
        {
            [MenuMap.None] = By.CssSelector("a[href='/']"),
            [MenuMap.Users] = By.CssSelector("a[href='/users']"),
            [MenuMap.Roles] = By.CssSelector("a[href='/roles']"),
            [MenuMap.StatUnits] = By.CssSelector("a[href='/statunits']"),
            [MenuMap.Account] = By.CssSelector("a[href='/account']"),
        };

        public static void SignInAsAdmin(RemoteWebDriver driver, MenuMap section)
        {
            SignIn(driver, "admin", "123qwe", section);
        }

        // ReSharper disable once MemberCanBePrivate.Global
        public static void SignIn(RemoteWebDriver driver, string login, string password, MenuMap section)
        {
            driver.FindElement(By.Name("login")).SendKeys(login);
            driver.FindElement(By.Name("password")).SendKeys(password);
            driver.FindElement(By.CssSelector("input[type='submit']")).Submit();
            driver.FindElement(ByMenu[section]).Click();
        }

        public static bool CheckLoadingNotification(RemoteWebDriver driver)
            => driver.FindElementByXPath("//*[@id=\"root\"]/div/main/div[1]/div/i") != null;
    }
}
