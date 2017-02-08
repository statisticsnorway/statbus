using System;
using OpenQA.Selenium;

namespace nscreg.Server.TestUI.Users
{
    public class UserPageResult
    {
        private readonly IWebDriver _driver;

        public UserPageResult(IWebDriver driver)
        {
            _driver = driver;
        }

        public string AddUserPage() => _driver.FindElement(By.XPath("//tbody/tr/td/a[text()='TestName']")).Text;

        public string EditUserPage() => _driver.FindElement(By.XPath("//tbody/tr/td/a[contains(text(),'TestName')]")).Text;

        public bool DeleteUserPage()
        {
            try
            {
               return _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Displayed;
            }
            catch (NoSuchElementException e)
            {
                return false;
            }
            catch (Exception e)
            {
                throw new Exception(e.Message);
            }
        } 
    }
}
