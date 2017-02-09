using System;
using OpenQA.Selenium;

namespace nscreg.Server.TestUI.Roles
{
    public class RolePageResult
    {
        private readonly IWebDriver _driver;

        public RolePageResult(IWebDriver driver)
        {
            _driver = driver;
        }

        public string AddRolePage(string name) => _driver
            .FindElement(By.XPath($"//tbody/tr/td/a[text()='{name}']"))
            .Text;

        public string EditRolePage(string name) => _driver
            .FindElement(By.XPath($"//tbody/tr/td/a[text()='{name}']"))
            .Text;

        public string DeleteRolePage(string name)
        {
            string result;
            try
            {
                result = _driver.FindElement(By.XPath($"//tbody/tr/td/a[text()='{name}']")).Text;
            }
            catch (Exception)
            {
                result = "nothing found";
            }

            return result;
        }

        public bool DisplayRolePage() => _driver
            .FindElement(By.XPath("//div[contains(@class, 'header')]/a"))
            .Displayed;
    }
}