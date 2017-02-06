using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using OpenQA.Selenium;

namespace UITest
{
    public class ResultStatUnitPage
    {
        private IWebDriver _driver;

        public ResultStatUnitPage(IWebDriver driver)
        {
            this._driver = driver;
        }

        public string AddStatUnitPage()
        {
            return _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Text;
        }

        public string EditStatInitPage()
        {
            return _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Text;
        }

        public string DeleteStatInitPage()
        {
            return _driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Text;
        }
    }
}