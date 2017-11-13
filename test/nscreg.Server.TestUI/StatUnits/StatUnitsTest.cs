using nscreg.Server.TestUI.Commons;
using Xunit;
using static nscreg.Server.TestUI.CommonScenarios;
using static nscreg.Server.TestUI.StatUnits.StatUnitPage;

namespace nscreg.Server.TestUI.StatUnits
{
    public class StatUnitsTest : SeleniumTestBase
    {
        #region PRIVATE STAT UNIT PROPS

        //LocalUnit
        private readonly string _localUnit_NameField = "LocalUnit";
        private readonly string _localUnit_NameFieldEdited = "Edited";
        private readonly string _localUnit_LegalUnitIdField = "legal unit 1";

        //LegalUnit
        private readonly string _legalUnit_NameField = "LegalUnit";
        private readonly string _legalUnit_NameFieldEdited = "Edited";
        private readonly string _enterpriseRegistrationId = "enterprise unit 1";

        //EnterpriceUnit
        private readonly string _enterpriceUnit_NameField = "EnterpriseUnit";
        private readonly string _enterpriseUnit_NameFieldEdited = "Edited";
        private readonly string _enterpriseGroupIdForAdd = "enterprise group 1";

        //EnterpriceUnit
        private readonly string _enterpriseGroup_NameField = "EnterpriseGroup";
        private readonly string _enterpriseGroup_NameFieldEdited = "Edited";

        #endregion

        #region LocalUnit
        [Fact, Order(0)]
        public void AddLocalUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            AddLocalUnitAct(Driver, _localUnit_NameField, _localUnit_LegalUnitIdField);
            Assert.True(IsStatUnitAdded(Driver, _localUnit_NameField));
        }

        [Fact, Order(1)]
        public void EditLocalUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            EditLocalUnitAct(Driver, _localUnit_NameFieldEdited);
            Assert.NotEqual(IsStatUnitEdited(Driver, _localUnit_NameFieldEdited), _localUnit_NameField);
        }

        [Fact, Order(2)]
        public void DeleteLocalUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            DeleteLocalUnitAct(Driver);
            Assert.False(IsDeleteStatUnit(Driver, _localUnit_NameFieldEdited));
        }
        #endregion


        #region LegalUnit

        [Fact, Order(3)]
        public void AddLegalUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            AddLegalUnitAct(Driver, _enterpriseRegistrationId, _legalUnit_NameField);
            Assert.True(IsStatUnitAdded(Driver, _legalUnit_NameField));
        }

        [Fact, Order(4)]
        public void EditLegalUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            EditLegalUnitAct(Driver, _legalUnit_NameFieldEdited);
            Assert.NotEqual(IsStatUnitEdited(Driver, _legalUnit_NameFieldEdited), (_legalUnit_NameField));
        }

        [Fact, Order(5)]
        public void DeleteLegalUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            DeleteLegalUnitAct(Driver);
            Assert.False(IsDeleteStatUnit(Driver, _legalUnit_NameFieldEdited));
        }

        #endregion


        #region EnterpriceUnit
        [Fact, Order(6)]
        public void AddEnterpriceUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            AddEnterpriceUnitAct(Driver,_enterpriseGroupIdForAdd, _enterpriceUnit_NameField);
            Assert.True(IsStatUnitAdded(Driver, _enterpriceUnit_NameField));
        }

        [Fact, Order(7)]
        public void EditEnterpriceUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            EditEnterpriceUnitAct(Driver, _enterpriseUnit_NameFieldEdited);
            Assert.NotEqual(IsStatUnitEdited(Driver, _enterpriseUnit_NameFieldEdited), _enterpriseGroupIdForAdd);
        }

        [Fact, Order(8)]
        public void DeleteEnterpriceUnit()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            DeleteEnterpriceUnitAct(Driver);
            Assert.False(IsDeleteStatUnit(Driver, _enterpriseUnit_NameFieldEdited));
        }

        #endregion

        #region EnterpriceGroup

        [Fact, Order(9)]
        public void AddEnterpriceGroup()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            AddEnterpriceGroupAct(Driver, _enterpriseGroup_NameField);
            Assert.True(IsStatUnitAdded(Driver, _enterpriseGroup_NameField));
        }

        [Fact, Order(10)]
        public void EditEnterpriceGgroup()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            EditEnterpriceGgroupAct(Driver, _enterpriseGroup_NameFieldEdited);
            Assert.NotEqual(IsStatUnitEdited(Driver, _enterpriseGroup_NameFieldEdited), (_enterpriseGroup_NameField));
        }

        [Fact, Order(11)]
        public void DeleteEnterpriceGroup()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            DeleteEnterpriceGroupAct(Driver);
            Assert.False(IsDeleteStatUnit(Driver, _enterpriseGroup_NameFieldEdited));
        }

        #endregion

        #region Search
        [Fact, Order(12)]
        public void AnyType()
        {
            SignInAsAdminAndNavigate(Driver, MenuMap.StatUnits);
            SearchAnyTypeAct(Driver);
            Assert.True(ShowAnyType(Driver));
        }

        #endregion
    }
}
