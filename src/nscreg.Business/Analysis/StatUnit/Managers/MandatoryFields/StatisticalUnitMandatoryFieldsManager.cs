using nscreg.Business.Analysis.Contracts;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis statistical unit mandatory fields manager
    /// </summary>
    public class StatisticalUnitMandatoryFieldsManager : IMandatoryFieldsAnalysisManager
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

            if (_mandatoryFields.StatUnit.DataSourceClassificationId && _statisticalUnit.DataSourceClassificationId == null)
                messages.Add(nameof(_statisticalUnit.DataSourceClassificationId), new[] { nameof(Resource.AnalysisMandatoryDataSource) });

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_statisticalUnit.Name))
                messages.Add(nameof(_statisticalUnit.Name), new[] { nameof(Resource.AnalysisMandatoryName) });

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
                    messages.Add(nameof(_statisticalUnit.ShortName),
                        new[] { nameof(Resource.AnalysisMandatoryShortName) });
                else if (_statisticalUnit.ShortName == _statisticalUnit.Name)
                    messages.Add(nameof(_statisticalUnit.ShortName),
                        new[] { nameof(Resource.AnalysisSameNameAsShortName) });
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_statisticalUnit.TelephoneNo))
                messages.Add(nameof(_statisticalUnit.TelephoneNo),
                    new[] { nameof(Resource.AnalysisMandatoryTelephoneNo) });

            if (_mandatoryFields.StatUnit.RegistrationReasonId && _statisticalUnit.RegistrationReasonId == null)
                messages.Add(nameof(_statisticalUnit.RegistrationReasonId),
                    new[] { nameof(Resource.AnalysisMandatoryRegistrationReason) });

            if (_mandatoryFields.StatUnit.SizeId && _statisticalUnit.SizeId == null)
            {
                messages.Add(nameof(_statisticalUnit.SizeId), new[] { nameof(Resource.AnalysisMandatorySize) });
            }

            if (_mandatoryFields.StatUnit.UnitStatusId && _statisticalUnit.UnitStatusId == null)
            {
                messages.Add(nameof(_statisticalUnit.UnitStatusId), new[] { nameof(Resource.AnalysisMandatoryUnitStatus) });
            }
            return messages;
        }

        public Dictionary<string, string[]> CheckOnlyIdentifiersFields()
        {
            var messages = new Dictionary<string, string[]>();
            var suStatUnitBools = new[]
            {
                _statisticalUnit.StatId != null,
                _statisticalUnit.TaxRegId != null,
                _statisticalUnit.ExternalId != null
            };
            if (!suStatUnitBools.Contains(true))
            {
                messages.Add(nameof(_statisticalUnit.RegId), new[] { Resource.AnalysisOneOfTheseFieldsShouldBeFilled });
            }
            return messages;
        }
    }
}
