using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using NUnit.Framework;
using NUnit.Framework.Internal;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Support.UI;
using UITest.Roles;
using Assert = NUnit.Framework.Assert;


namespace UITest.StatUnits
{
    [TestFixture]
    public class StatInit
    {
        ChromeDriver _driver;
        private string _type = "";
        private string _statisticalId = "";
        private string _taxRegistrationId = "";
        private string _taxRegistrationId2 = "";
        private string _taxRegistrationDate = "";
        private string _externalId = "";
        private string _externalIdType = "";
        private string _externalIdDate = "";
        private string _dataSource = "";
        private string _referenceNo= "";
        private string _Name = "";
        private string _shortName = "";
        private string _postalAddressId = "";
        private string _telephonNo = "";
        private string _email = "";
        private string _webAddress = "";
        private string _registrationMainActivity = "";
        private string _registrationDate = "";
        private string _registrationReason = "";
        private string _liquidationDate = "";
        private string _liquidationReason = "";
        private string _suspensionStart = "";
        private string _suspensionEnd = "";
        private string _reorganizationTypeCode = "";
        private string _reorganizationDate= "";
        private string _reorganizationReferences= "";
        private string _actualAddress = "";
        private string _employees = "";
        private string _numberOfPeople = "";
        private string _employeesYear = "";
        private string _employeesDate= "";
        private string _turnover = "";
        private string _turnoverYear= "";
        private string _turnoverDate = "";
        private string _status = "";
        private string _statusDate = "";
        private bool   _freeEconomicZone;
        private string _foreignParticipation2 = "";
        private string _classified = "";
        private string _legalUnitId = "";
        private string _enterpriseUnit = "";
        private string _legalUnitIdDate= "";




        [SetUp]
        public void Setup()
        {
            _driver = new ChromeDriver();
        }


         //[Test]
        public void AddStatInit()
        {
            StatUnitPage home = new StatUnitPage(_driver);
            ResultStatUnitPage resultStatUnit = home.AddStatUnitAct();
            Assert.IsTrue(resultStatUnit.AddStatUnitPage().Contains());
        }

        //[Test]
        public void EditStatInit()
        {
            StatUnitPage home = new StatUnitPage(_driver);
            ResultStatUnitPage resultStatUnit = home.EditStatUnitAct();
            Assert.IsTrue(resultStatUnit.EditStatInitPage().Contains());
        }

        //[Test]
        public void DeleteStatInit()
        {
            StatUnitPage home = new StatUnitPage(_driver);
            ResultStatUnitPage resultStatUnit = home.DeleteStatUnitAct();
            Assert.IsFalse(resultStatUnit.DeleteStatInitPage().Contains());
        }

        [TearDown]
        public void TearDown()
        {
           _driver.Quit();
        }

    }
}
