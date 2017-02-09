using Xunit;

namespace nscreg.Server.TestUI.StatUnits
{
    public class StatUnitsTest : SeleniumTestBase
    {
        #region PRIVATE STAT UNIT PROPS

        private readonly string _type = "";
        private readonly string _statisticalId = "";
        private readonly string _taxRegistrationId = "";
        private readonly string _taxRegistrationId2 = "";
        private readonly string _taxRegistrationDate = "";
        private readonly string _externalId = "";
        private readonly string _externalIdType = "";
        private readonly string _externalIdDate = "";
        private readonly string _dataSource = "";
        private readonly string _referenceNo = "";
        private readonly string _Name = "";
        private readonly string _shortName = "";
        private readonly string _postalAddressId = "";
        private readonly string _telephonNo = "";
        private readonly string _email = "";
        private readonly string _webAddress = "";
        private readonly string _registrationMainActivity = "";
        private readonly string _registrationDate = "";
        private readonly string _registrationReason = "";
        private readonly string _liquidationDate = "";
        private readonly string _liquidationReason = "";
        private readonly string _suspensionStart = "";
        private readonly string _suspensionEnd = "";
        private readonly string _reorganizationTypeCode = "";
        private readonly string _reorganizationDate = "";
        private readonly string _reorganizationReferences = "";
        private readonly string _actualAddress = "";
        private readonly string _employees = "";
        private readonly string _numberOfPeople = "";
        private readonly string _employeesYear = "";
        private readonly string _employeesDate = "";
        private readonly string _turnover = "";
        private readonly string _turnoverYear = "";
        private readonly string _turnoverDate = "";
        private readonly string _status = "";
        private readonly string _statusDate = "";
        private readonly bool _freeEconomicZone;
        private readonly string _foreignParticipation2 = "";
        private readonly string _classified = "";
        private readonly string _legalUnitId = "";
        private readonly string _enterpriseUnit = "";
        private readonly string _legalUnitIdDate = "";

        #endregion

        [Fact]
        public void AddStatInit()
        {
            var page = new StatUnitPage(Driver);
            //StatUnitPageResult resultStatUnit = page.AddStatUnitAct();
            //Assert.True(resultStatUnit.AddStatUnitPage().Contains());
        }

        [Fact]
        public void EditStatInit()
        {
            var page = new StatUnitPage(Driver);
            //StatUnitPageResult resultStatUnit = page.EditStatUnitAct();
            //Assert.True(resultStatUnit.EditStatInitPage().Contains());
        }

        [Fact]
        public void DeleteStatInit()
        {
            var page = new StatUnitPage(Driver);
            //StatUnitPageResult resultStatUnit = page.DeleteStatUnitAct();
            //Assert.False(resultStatUnit.DeleteStatInitPage().Contains());
        }

        [Fact]
        public void SearchStatUnit()
        {
            var page = new StatUnitPage(Driver);

            var result = page.Search();

            Assert.True(result);
        }
    }
}
