using System.Collections.Generic;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI
{
    public static class CommonScenarios
    {
        private static readonly By AdminMenu = By.XPath("//div[text()='Administrative tools']");
        private static readonly By Sidebar = By.CssSelector("i.sidebar");

        private static readonly Dictionary<MenuMap, IEnumerable<By>> ByMenu = new Dictionary<MenuMap, IEnumerable<By>>
        {
            [MenuMap.None] = new List<By> { Sidebar, By.CssSelector("a[href='/']")},
            [MenuMap.Users] = new List<By> { Sidebar, AdminMenu, By.CssSelector("a[href='/users']")},
            [MenuMap.Roles] = new List<By> { Sidebar, AdminMenu, By.CssSelector("a[href='/roles']")},
            [MenuMap.Regions] = new List<By> { Sidebar, AdminMenu, By.CssSelector("a[href='/regions']")},
            [MenuMap.StatUnits] = new List<By> { Sidebar, By.CssSelector("a[href='/statunits']")},
            [MenuMap.Account] = new List<By> { Sidebar, By.CssSelector("a[href='/account']")}
        };

        public static void SignInAsAdminAndNavigate(RemoteWebDriver driver, MenuMap section)
        {
            SignIn(driver, "admin", "123qwe", section);
        }

        // ReSharper disable once MemberCanBePrivate.Global
        public static void SignIn(RemoteWebDriver driver, string login, string password, MenuMap section)
        {
            driver.FindElement(By.Name("login")).SendKeys(login);
            driver.FindElement(By.Name("password")).SendKeys(password);
            driver.FindElement(By.CssSelector("input[type='submit']")).Submit();
            
            foreach (var link in ByMenu[section])
            {
                driver.FindElement(link).Click();
            }
        }
    }
}
