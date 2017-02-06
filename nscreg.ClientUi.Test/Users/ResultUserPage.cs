using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using OpenQA.Selenium;

namespace UITest.Users
{
   public class ResultUserPage
    {
        private IWebDriver _driver;

        public ResultUserPage(IWebDriver driver)
        {
            this._driver = driver;
        }


        public string AddUserPage()
        {
            return _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Text;
        }

        public string EditUserPage()
        {
            return _driver.FindElement(By.XPath("//tbody[1]/tr/td[1]/a")).Text;
        }

        public bool DeleteUserPage()
        {
            return  _driver.FindElement(By.XPath("//tbody[2]/tr/td[1]/a")).Displayed;
        }
    }
}
