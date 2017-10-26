using System.Linq;
using nscreg.Data.Entities;
using nscreg.Data.Constants;
using System.Collections.Generic;
using nscreg.Business.Analysis.Contracts;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using LegalUnit = nscreg.Data.Entities.LegalUnit;

namespace nscreg.Business.Analysis.StatUnit.Managers
{
    /// <summary>
    /// Stat unit analysis mandatory fields manager
    /// </summary>
    public class StatisticalUnitMandatoryFieldsManager : IAnalysisManager
    {
        private readonly StatisticalUnit _statisticalUnit;
        private readonly DbMandatoryFields _mandatoryFields;

        public StatisticalUnitMandatoryFieldsManager(StatisticalUnit unit, DbMandatoryFields mandatoryFields)
        {
            _statisticalUnit = unit;
            _mandatoryFields = mandatoryFields;
        }

        public Dictionary<string, string[]> CheckFields()
        {
            var messages = new Dictionary<string, string[]>();

            if (_mandatoryFields.StatUnit.DataSource && string.IsNullOrEmpty(_statisticalUnit.DataSource))
                messages.Add(nameof(_statisticalUnit.DataSource), new[] { "Stat unit doesn't have data source" });

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_statisticalUnit.Name))
                messages.Add(nameof(_statisticalUnit.Name), new[] { "Stat unit doesn't have name" });

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
                    messages.Add(nameof(_statisticalUnit.ShortName), new[] { "Stat unit doesn't have short name" });
                else if (_statisticalUnit.ShortName == _statisticalUnit.Name)
                    messages.Add(nameof(_statisticalUnit.ShortName), new[] { "Stat unit's short name is the same as name" });
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_statisticalUnit.TelephoneNo))
                messages.Add(nameof(_statisticalUnit.TelephoneNo), new[] { "Stat unit doesn't have telephone number" });

            if (_mandatoryFields.StatUnit.RegistrationReason && string.IsNullOrEmpty(_statisticalUnit.RegistrationReason))
                messages.Add(nameof(_statisticalUnit.RegistrationReason), new[] { "Stat unit doesn't have registration reason" });

            if (_mandatoryFields.StatUnit.ContactPerson && string.IsNullOrEmpty(_statisticalUnit.ContactPerson))
                messages.Add(nameof(_statisticalUnit.ContactPerson), new[] { "Stat unit doesn't have contact person" });

            if (_statisticalUnit.RegId > 0 && _statisticalUnit.Status != StatUnitStatuses.Active)
                messages.Add(nameof(_statisticalUnit.Status), new[] {"Stat unit's status is not \"active\""});

            if (_statisticalUnit is LegalUnit legalUnit && legalUnit.PersonsUnits.All(pu => pu.PersonType != PersonTypes.Owner))
                messages.Add(nameof(_statisticalUnit.Persons), new[] {"Legal unit doesn't have any person with \"Owner\" status"});

            return messages;
        }
        
    }
}
