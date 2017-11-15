using System;
using OpenQA.Selenium;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI.StatUnits
{
    public static class StatUnitPage
    {
        #region ACTIONS

        #region LocalUnit

        public static void AddLocalUnitAct(RemoteWebDriver driver, string nameField, string legalUnitIdField)
        {
            driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();
            driver.FindElement(By.XPath("//label[text()='Legal unit id']/../div")).Click();
            driver.FindElement(By.XPath($"//div[contains(@class, 'item')][text()='{legalUnitIdField}']")).Click();

            driver.FindElement(By.Name("name")).SendKeys(nameField);
            driver.FindElement(By.XPath("//button")).Click();

            driver.Manage().Timeouts().ImplicitWait = TimeSpan.FromSeconds(2);
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Local unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void EditLocalUnitAct(RemoteWebDriver driver, string nameForEdit)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Local unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//a[contains(@class, 'ui icon primary button')])[last()]")).Click();
            driver.FindElement(By.Name("name")).Clear();
            driver.FindElement(By.Name("name")).SendKeys(nameForEdit);
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Local unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void DeleteLocalUnitAct(RemoteWebDriver driver)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Local unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//button[contains(@class, 'ui icon negative right floated button')])[last()]"))
                .Click();
            System.Threading.Thread.Sleep(1000);
            IAlert deleteAlert = driver.SwitchTo().Alert();
            deleteAlert.Accept();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Local unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        #endregion

        #region LegalUnit

        public static void AddLegalUnitAct(RemoteWebDriver driver, string enterpriseRegistrationId, string name)
        {
            driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'ui selection dropdown')]")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Legal unit']")).Click();

            driver.FindElement(By.XPath("//label[text()='Enterprise registration id']/../div")).Click();
            driver.FindElement(By.XPath($"//div[contains(@class, 'item')][text()='{enterpriseRegistrationId}']"))
                .Click();
            driver.FindElement(By.Name("name")).SendKeys(name);
            driver.FindElement(By.XPath("//button")).Click();


            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Legal unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void EditLegalUnitAct(RemoteWebDriver driver, string nameEdited)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Legal unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//a[contains(@class, 'ui icon primary button')])[last()]")).Click();
            driver.FindElement(By.Name("name")).Clear();
            driver.FindElement(By.Name("name")).SendKeys(nameEdited);
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Legal unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void DeleteLegalUnitAct(RemoteWebDriver driver)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Legal unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//button[contains(@class, 'ui icon negative right floated button')])[last()]"))
                .Click();
            System.Threading.Thread.Sleep(1000);
            IAlert deleteAlert = driver.SwitchTo().Alert();
            deleteAlert.Accept();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Legal unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        #endregion

        #region EnterpriceUnit

        public static void AddEnterpriceUnitAct(RemoteWebDriver driver, string enterpriseGroupId, string name)
        {
            driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'ui selection dropdown')]")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise unit']")).Click();

            driver.FindElement(By.XPath("//label[text()='Enterprise group id']/../div")).Click();
            driver.FindElement(By.XPath($"//div[contains(@class, 'selected item')][text()='{enterpriseGroupId}']"))
                .Click();
            driver.FindElement(By.Name("name")).SendKeys(name);
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("//label[text()='LegalUnits']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='legal unit 1']")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='legal unit 2']")).Click();

            driver.FindElement(By.XPath("//label[text()='LocalUnits']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='local unit 1']")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='local unit 2']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void EditEnterpriceUnitAct(RemoteWebDriver driver, string nameEdited)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//a[contains(@class, 'ui icon primary button')])[last()]")).Click();
            driver.FindElement(By.Name("name")).Clear();
            driver.FindElement(By.Name("name")).SendKeys(nameEdited);
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void DeleteEnterpriceUnitAct(RemoteWebDriver driver)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//button[contains(@class, 'ui icon negative right floated button')])[last()]"))
                .Click();
            System.Threading.Thread.Sleep(1000);
            IAlert deleteAlert = driver.SwitchTo().Alert();
            deleteAlert.Accept();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise unit']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        #endregion

        #region EnterpriceGroup

        public static void AddEnterpriceGroupAct(RemoteWebDriver driver, string name)
        {
            driver.FindElement(By.XPath("//a[contains(@class, 'ui green medium button')]")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'ui selection dropdown')]")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise group']")).Click();

            driver.FindElement(By.Name("name")).SendKeys(name);
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("//label[text()='EnterpriseUnits']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='enterprise unit 1']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void EditEnterpriceGgroupAct(RemoteWebDriver driver, string nameEdited)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise group']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//a[contains(@class, 'ui icon primary button')])[last()]")).Click();
            driver.FindElement(By.Name("name")).Clear();
            driver.FindElement(By.Name("name")).SendKeys(nameEdited);
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise group']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        public static void DeleteEnterpriceGroupAct(RemoteWebDriver driver)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise group']")).Click();
            driver.FindElement(By.XPath("//button")).Click();

            driver.FindElement(By.XPath("(//button[contains(@class, 'ui icon negative right floated button')])[last()]"))
                .Click();
            System.Threading.Thread.Sleep(1000);
            IAlert deleteAlert = driver.SwitchTo().Alert();
            deleteAlert.Accept();

            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Enterprise group']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        #endregion

        #region Searches

        public static void SearchAnyTypeAct(RemoteWebDriver driver)
        {
            driver.FindElement(By.XPath("//label[text()='Statistical unit type']/../div")).Click();
            driver.FindElement(By.XPath("//div[contains(@class, 'item')][text()='Any type']")).Click();
            driver.FindElement(By.XPath("//button")).Click();
        }

        #endregion

        #endregion

        #region ASSERTIONS

        public static bool IsStatUnitAdded(RemoteWebDriver driver, string name)
        {
            driver.FindElement(By.XPath("//form/div[1]/div/input")).SendKeys(name);
            driver.FindElement(By.XPath("//button[text()='Search']")).Click();
            return driver.FindElement(By.XPath($"//div[contains(@class, 'header')]/a[text()='{name}']")).Displayed;
        }

        public static string IsStatUnitEdited(RemoteWebDriver driver, string nameEdited) =>
            driver.FindElement(By.XPath($"//div[contains(@class, 'header')]/a[text()='{nameEdited}']")).Text;

        public static bool IsDeleteStatUnit(RemoteWebDriver driver, string nameEdited)
        {
            try
            {
                driver.FindElement(By.XPath($"//div[contains(@class, 'header')]/a[text()='{nameEdited}']"));
                return true;
            }
            catch (NoSuchElementException)
            {
                return false;
            }
        }

        public static bool ShowAnyType(RemoteWebDriver driver) =>
            driver.FindElement(By.XPath("//div[contains(@class, 'content')]")).Displayed;

        #endregion
    }
}
