using nscreg.Business.Analysis.Contracts;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using System.Collections.Generic;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using System.Linq;

namespace nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis enterprise group mandatory fields manager
    /// </summary>
    public class EnterpriseGroupMandatoryFieldsManager : IMandatoryFieldsAnalysisManager
    {
        private readonly EnterpriseGroup _enterpriseGroup;
        private readonly DbMandatoryFields _mandatoryFields;

        public EnterpriseGroupMandatoryFieldsManager(EnterpriseGroup enterpriseGroup, DbMandatoryFields mandatoryFields)
        {
            _enterpriseGroup = enterpriseGroup;
            _mandatoryFields = mandatoryFields;
        }

        /// <summary>
        /// Check mandatory fields 
        /// </summary>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckFields()
        {
            var messages = new Dictionary<string, string[]>();

            if (_mandatoryFields.EnterpriseGroup.DataSourceClassificationId && _enterpriseGroup.DataSourceClassificationId == null)
                messages.Add(nameof(_enterpriseGroup.DataSource), new[] { nameof(Resource.AnalysisMandatoryDataSource) });

            if (_mandatoryFields.EnterpriseGroup.Name && string.IsNullOrEmpty(_enterpriseGroup.Name))
                messages.Add(nameof(_enterpriseGroup.Name), new[] { nameof(Resource.AnalysisMandatoryName) });

            if (_mandatoryFields.EnterpriseGroup.ShortName)
            {
                if (string.IsNullOrEmpty(_enterpriseGroup.ShortName))
                    messages.Add(nameof(_enterpriseGroup.ShortName), new[] { nameof(Resource.AnalysisMandatoryShortName) });
                else if (_enterpriseGroup.ShortName == _enterpriseGroup.Name)
                    messages.Add(nameof(_enterpriseGroup.ShortName), new[] { nameof(Resource.AnalysisSameNameAsShortName) });
            }

            if (_mandatoryFields.EnterpriseGroup.TelephoneNo && string.IsNullOrEmpty(_enterpriseGroup.TelephoneNo))
                messages.Add(nameof(_enterpriseGroup.TelephoneNo), new[] { nameof(Resource.AnalysisMandatoryTelephoneNo) });

            if (_mandatoryFields.EnterpriseGroup.ContactPerson && string.IsNullOrEmpty(_enterpriseGroup.ContactPerson))
                messages.Add(nameof(_enterpriseGroup.ContactPerson), new[] { nameof(Resource.AnalysisMandatoryContactPerson) });

            return messages;
        }

        public Dictionary<string, string[]> CheckOnlyIdentifiersFields()
        {
            var messages = new Dictionary<string, string[]>();
            var suStatUnitBools = new[]
            {
                _enterpriseGroup.StatId != null,
                _enterpriseGroup.TaxRegId != null,
                _enterpriseGroup.ExternalId != null
            };
            if (!suStatUnitBools.Contains(true))
            {
                messages.Add(nameof(_enterpriseGroup.RegId), new[] { Resource.AnalysisOneOfTheseFieldsShouldBeFilled });
            }
            return messages;
        }
    }
}
