using System.Linq;
using nscreg.Data.Entities;
using nscreg.Data.Constants;
using System.Collections.Generic;
using nscreg.Business.Analysis.Contracts;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using LegalUnit = nscreg.Data.Entities.LegalUnit;

namespace nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis statistical unit mandatory fields manager
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

        /// <summary>
        /// Check mandatory fields
        /// </summary>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckFields()
        {
            var messages = new Dictionary<string, string[]>();

            if (_mandatoryFields.StatUnit.DataSource && string.IsNullOrEmpty(_statisticalUnit.DataSource))
                messages.Add(nameof(_statisticalUnit.DataSource), new[] { Resource.AnalysisMandatoryDataSource });

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_statisticalUnit.Name))
                messages.Add(nameof(_statisticalUnit.Name), new[] { Resource.AnalysisMandatoryName });

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
                    messages.Add(nameof(_statisticalUnit.ShortName), new[] { Resource.AnalysisMandatoryShortName });
                else if (_statisticalUnit.ShortName == _statisticalUnit.Name)
                    messages.Add(nameof(_statisticalUnit.ShortName), new[] { Resource.AnalysisSameNameAsShortName });
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_statisticalUnit.TelephoneNo))
                messages.Add(nameof(_statisticalUnit.TelephoneNo), new[] { Resource.AnalysisMandatoryTelephoneNo });

            if (_mandatoryFields.StatUnit.RegistrationReason &&
                string.IsNullOrEmpty(_statisticalUnit.RegistrationReason))
                messages.Add(nameof(_statisticalUnit.RegistrationReason),
                    new[] { Resource.AnalysisMandatoryRegistrationReason });

            if (_mandatoryFields.StatUnit.ContactPerson && string.IsNullOrEmpty(_statisticalUnit.ContactPerson))
                messages.Add(nameof(_statisticalUnit.ContactPerson), new[] { Resource.AnalysisMandatoryContactPerson });

            if (_statisticalUnit.RegId > 0 && _statisticalUnit.Status != StatUnitStatuses.Active)
                messages.Add(nameof(_statisticalUnit.Status), new[] { Resource.AnalysisMandatoryStatusActive });

            if (_statisticalUnit is LegalUnit legalUnit &&
                legalUnit.PersonsUnits.All(pu => pu.PersonType != PersonTypes.Owner))
                messages.Add(nameof(_statisticalUnit.Persons), new[] { Resource.AnalysisMandatoryPersonOwner });

            return messages;
        }
    }
}
