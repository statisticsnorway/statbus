using System.Collections.Generic;
using nscreg.Business.Analysis.Contracts;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;

namespace nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis enterprise group mandatory fields manager
    /// </summary>
    public class EnterpriseGroupMandatoryFieldsManager : IAnalysisManager
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

            if (_mandatoryFields.StatUnit.DataSource && string.IsNullOrEmpty(_enterpriseGroup.DataSource))
                messages.Add(nameof(_enterpriseGroup.DataSource), new[] { Resource.AnalysisMandatoryDataSource });

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_enterpriseGroup.Name))
                messages.Add(nameof(_enterpriseGroup.Name), new[] { Resource.AnalysisMandatoryName });

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_enterpriseGroup.ShortName))
                    messages.Add(nameof(_enterpriseGroup.ShortName), new[] { Resource.AnalysisMandatoryShortName });
                else if (_enterpriseGroup.ShortName == _enterpriseGroup.Name)
                    messages.Add(nameof(_enterpriseGroup.ShortName), new[] { Resource.AnalysisSameNameAsShortName });
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_enterpriseGroup.TelephoneNo))
                messages.Add(nameof(_enterpriseGroup.TelephoneNo), new[] { Resource.AnalysisMandatoryTelephoneNo });

            if (_mandatoryFields.StatUnit.RegistrationReason &&
                string.IsNullOrEmpty(_enterpriseGroup.RegistrationReason))
                messages.Add(nameof(_enterpriseGroup.RegistrationReason),
                    new[] { Resource.AnalysisMandatoryRegistrationReason });

            if (_mandatoryFields.StatUnit.ContactPerson && string.IsNullOrEmpty(_enterpriseGroup.ContactPerson))
                messages.Add(nameof(_enterpriseGroup.ContactPerson), new[] { Resource.AnalysisMandatoryContactPerson });

            return messages;
        }
    }
}
