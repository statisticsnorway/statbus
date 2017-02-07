using OpenQA.Selenium;

namespace nscreg.Server.TestUI.StatUnits
{
    public class StatUnitPageResult
    {
        private readonly IWebDriver _driver;

        public StatUnitPageResult(IWebDriver driver)
        {
            _driver = driver;
        }

        public string AddStatUnitPage() => _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Text;

        public string EditStatInitPage() => _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Text;

        public string DeleteStatInitPage()
            => _driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Text;
    }
}
