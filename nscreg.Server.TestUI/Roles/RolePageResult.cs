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

        public string AddRolePage() => _driver
            .FindElement(By.XPath("//tbody[2]/tr/td[1]/a"))
            .Text;

        public string EditRolePage() => _driver
            .FindElement(By.XPath("//tbody[1]/tr/td[1]/a"))
            .Text;

        public string DeleteRolePage() => _driver
            .FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]"))
            .Text;

        public bool DisplayRolePage() => _driver
            .FindElement(By.XPath("//div[contains(@class, 'header')]/a"))
            .Displayed;
    }
}
