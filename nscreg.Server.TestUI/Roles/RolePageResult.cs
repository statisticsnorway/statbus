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

        public string RolePage(string name)
        {
            string result;
            try
            {
                result = _driver.FindElement(By.XPath($"//a[text()='{name}']")).Text;
            }
            catch (Exception)
            {
                result = "nothing found";
            }

            return result;
        }
    }
}