using System.Linq;
using nscreg.Data.Entities;
using nscreg.Data.Constants;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    public class MandatoryFieldsManager
    {
        private readonly StatisticalUnit _statisticalUnit;
        private readonly IStatisticalUnit _unit;

        public MandatoryFieldsManager(IStatisticalUnit unit)
        {
            _statisticalUnit = (StatisticalUnit) unit;
            _unit = unit;
        }

        public (string, string[]) CheckDataSource()
        {
            return !string.IsNullOrEmpty(_unit.DataSource)
                ? (null, null)
                : (nameof(_unit.DataSource), new[] {"Stat unit doesn't have data source"});
        }

        public (string, string[]) CheckName()
        {
            return !string.IsNullOrEmpty(_unit.Name)
                ? (null, null)
                : (nameof(_unit.Name), new[] { "Stat unit doesn't have name" });
        }

        public (string, string[]) CheckShortName()
        {
            if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
            {
                return (nameof(_statisticalUnit.ShortName), new[] {"Stat unit doesn't have short name"});
            }

            return _statisticalUnit.ShortName == _statisticalUnit.Name
                ? (nameof(_statisticalUnit.ShortName), new[] {"Stat unit's short name is the same as name"})
                : (null, null);
        }
        
        public (string, string[]) CheckTelephoneNo()
        {
            return !string.IsNullOrEmpty(_statisticalUnit.TelephoneNo)
                ? (null, null)
                : (nameof(_statisticalUnit.TelephoneNo), new[] { "Stat unit doesn't have telephone number" });
        }

        public (string, string[]) CheckRegistrationReason()
        {
            return !string.IsNullOrEmpty(_statisticalUnit.RegistrationReason)
                ? (null, null)
                : (nameof(_statisticalUnit.RegistrationReason), new[] { "Stat unit doesn't have registration reason" });
        }

        public (string, string[]) CheckContactPerson()
        {
            return !string.IsNullOrEmpty(_statisticalUnit.ContactPerson)
                ? (null, null)
                : (nameof(_statisticalUnit.ContactPerson), new[] { "Stat unit doesn't have contact person" });
        }

        public (string, string[]) CheckStatus()
        {
            return _statisticalUnit.Status == StatUnitStatuses.Active
                ? (null, null)
                : (nameof(_statisticalUnit.Status), new[] { "Stat unit's status is not \"active\"" });
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
