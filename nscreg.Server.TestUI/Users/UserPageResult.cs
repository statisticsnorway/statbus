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

        public string AddUserPage() => _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Text;

        public string EditUserPage() => _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Text;

        public bool DeleteUserPage() => _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Displayed;
    }
}
