using System.Linq;
using nscreg.Data.Entities;
using nscreg.Data.Constants;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    /// <summary>
    /// Stat unit analysis mandatory fields manager
    /// </summary>
    public class MandatoryFieldsManager
    {
        private readonly StatisticalUnit _statisticalUnit;
        private readonly IStatisticalUnit _unit;
        private readonly EnterpriseGroup _enterpriseGroup;

        public MandatoryFieldsManager(IStatisticalUnit unit)
        {
            _unit = unit;
            _enterpriseGroup = _unit as EnterpriseGroup;
            _statisticalUnit = _enterpriseGroup == null ? (StatisticalUnit) unit : null;
        }

        public (string, string[]) CheckDataSource()
        {
            return _enterpriseGroup == null
                ? !string.IsNullOrEmpty(_unit.DataSource)
                    ? (null, null)
                    : (nameof(_unit.DataSource), new[] {"Stat unit doesn't have data source"})
                : !string.IsNullOrEmpty(_enterpriseGroup.DataSource)
                    ? (null, null)
                    : (nameof(_enterpriseGroup.DataSource), new[] {"Stat unit doesn't have data source"});
        }

        public (string, string[]) CheckName()
        {
            return _enterpriseGroup == null
                ? !string.IsNullOrEmpty(_unit.Name)
                    ? (null, null)
                    : (nameof(_unit.Name), new[] {"Stat unit doesn't have name"})
                : !string.IsNullOrEmpty(_enterpriseGroup.Name)
                    ? (null, null)
                    : (nameof(_enterpriseGroup.Name), new[] {"Stat unit doesn't have name"});
        }

        public (string, string[]) CheckShortName()
        {
            if (_enterpriseGroup == null)
            {
                if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
                    return (nameof(_statisticalUnit.ShortName), new[] {"Stat unit doesn't have short name"});

                return _statisticalUnit.ShortName == _statisticalUnit.Name
                    ? (nameof(_statisticalUnit.ShortName), new[] {"Stat unit's short name is the same as name"})
                    : (null, null);
            }
            if (string.IsNullOrEmpty(_enterpriseGroup.ShortName))
                return (nameof(_enterpriseGroup.ShortName), new[] { "Stat unit doesn't have short name" });

            return _enterpriseGroup.ShortName == _enterpriseGroup.Name
                ? (nameof(_enterpriseGroup.ShortName), new[] { "Stat unit's short name is the same as name" })
                : (null, null);
        }

        public (string, string[]) CheckTelephoneNo()
        {
            return _enterpriseGroup == null
                ? !string.IsNullOrEmpty(_statisticalUnit.TelephoneNo)
                    ? (null, null)
                    : (nameof(_statisticalUnit.TelephoneNo), new[] {"Stat unit doesn't have telephone number"})
                : !string.IsNullOrEmpty(_enterpriseGroup.TelephoneNo)
                    ? (null, null)
                    : (nameof(_enterpriseGroup.TelephoneNo), new[] {"Stat unit doesn't have telephone number"});
        }

        public (string, string[]) CheckRegistrationReason()
        {
            return _enterpriseGroup == null
                ? !string.IsNullOrEmpty(_statisticalUnit.RegistrationReason)
                    ? (null, null)
                    : (nameof(_statisticalUnit.RegistrationReason), new[]
                        {"Stat unit doesn't have registration reason"})
                : !string.IsNullOrEmpty(_enterpriseGroup.RegistrationReason)
                    ? (null, null)
                    : (nameof(_enterpriseGroup.RegistrationReason), new[]
                        {"Stat unit doesn't have registration reason"});
        }

        public (string, string[]) CheckContactPerson()
        {
            return _enterpriseGroup == null
                ? !string.IsNullOrEmpty(_statisticalUnit.ContactPerson)
                    ? (null, null)
                    : (nameof(_statisticalUnit.ContactPerson), new[] {"Stat unit doesn't have contact person"})
                : !string.IsNullOrEmpty(_enterpriseGroup.ContactPerson)
                    ? (null, null)
                    : (nameof(_enterpriseGroup.ContactPerson), new[] {"Stat unit doesn't have contact person"});
        }

        public (string, string[]) CheckStatus()
        {
            return _enterpriseGroup == null
                ? _statisticalUnit.Status == StatUnitStatuses.Active
                    ? (null, null)
                    : (nameof(_statisticalUnit.Status), new[] {"Stat unit's status is not \"active\""})
                : (null, null);
        }

        public (string, string[]) CheckLegalUnitOwner()
        {
            var legalUnit = _unit as LegalUnit;
            if (legalUnit == null) return (null, null);
            
            return legalUnit.PersonsUnits.Any(pu => pu.PersonType == PersonTypes.Owner)
                ? (null, null)
                : (nameof(_statisticalUnit.Persons), new[] { "Legal unit doesn't have any person with \"Owner\" status" });
        }
    }
}
