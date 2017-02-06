using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using OpenQA.Selenium;

namespace UITest
{
    public class ResultRolePage
    {
        private IWebDriver _driver;

        public ResultRolePage(IWebDriver driver)
        {
            this._driver = driver;
        }

        public string MainPage()
        {
            return _driver.FindElement(By.XPath("//div[contains(@class, 'text')]")).Text;
        }

        public string AddRolePage()
        {
            return _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Text;
        }

        public string EditRolePage()
        {
            return _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Text;
        }

        public string DeleteRolePage()
        {
            return _driver.FindElement(By.XPath("(//button[contains(@class, 'ui red icon button')])[last()]")).Text;
        }

        public bool DisplayRolePage()
        {
            return _driver.FindElement(By.XPath("//div[contains(@class, 'header')]/a")).Displayed;
        }
    }
}
