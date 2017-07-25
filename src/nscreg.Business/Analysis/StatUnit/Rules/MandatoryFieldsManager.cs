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

        public void CheckDataSource(ref string key, ref string[] value)
        {
            if (!string.IsNullOrEmpty(_unit.DataSource)) return;
            key = nameof(_unit.DataSource);
            value = new[] {"Stat unit doesn't have data source"};
        }

        public void CheckName(ref string key, ref string[] value)
        {
            if (!string.IsNullOrEmpty(_unit.Name)) return;
            key = nameof(_unit.Name);
            value = new[] {"Stat unit doesn't have name"};
        }

        public void CheckShortName(ref string key, ref string[] value)
        {
            if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
            {
                key = nameof(_statisticalUnit.ShortName);
                value = new[] {"Stat unit doesn't have short name"};
            }
            else if (_statisticalUnit.ShortName == _statisticalUnit.Name)
            {
                key = nameof(_statisticalUnit.ShortName);
                value = new[] {"Stat unit's short name is the same as name"};
            }
        }
        
        public void CheckTelephoneNo(ref string key, ref string[] value)
        {
            if (!string.IsNullOrEmpty(_statisticalUnit.TelephoneNo)) return;
            key = nameof(_statisticalUnit.TelephoneNo);
            value = new[] {"Stat unit doesn't have telephone number"};
        }

        public void CheckRegistrationReason(ref string key, ref string[] value)
        {
            if (!string.IsNullOrEmpty(_statisticalUnit.RegistrationReason)) return;
            key = nameof(_statisticalUnit.RegistrationReason);
            value = new[] {"Stat unit doesn't have registration reason"};
        }

        public void CheckContactPerson(ref string key, ref string[] value)
        {
            if (!string.IsNullOrEmpty(_statisticalUnit.ContactPerson)) return;
            key = nameof(_statisticalUnit.ContactPerson);
            value = new[] {"Stat unit doesn't have contact person"};
        }

        public void CheckStatus(ref string key, ref string[] value)
        {
            if (_statisticalUnit.Status == StatUnitStatuses.Active) return;
            key = nameof(_statisticalUnit.Status);
            value = new[] {"Stat unit's status is not \"active\""};
        }

        public void CheckLegalUnitOwner(ref string key, ref string[] value)
        {
            var legalUnit = _unit as LegalUnit;
            if (legalUnit == null) return;
            
            if (legalUnit.PersonsUnits.Any(pu => pu.PersonType == PersonTypes.Owner)) return;
            key = nameof(_statisticalUnit.Persons);
            value = new[] {"Legal unit doesn't have any person with \"Owner\" status"};
        }
    }
}
