using System.Collections.Generic;
using nscreg.Business.Analysis.Contracts;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;

namespace nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields
{
    /// <summary>
    /// Enterprise group analysis mandatory fields manager
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

        public Dictionary<string, string[]> CheckFields()
        {
            var messages = new Dictionary<string, string[]>();

            if (_mandatoryFields.StatUnit.DataSource && string.IsNullOrEmpty(_enterpriseGroup.DataSource))
                messages.Add(nameof(_enterpriseGroup.DataSource), new[] {"Stat unit doesn't have data source"});

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_enterpriseGroup.Name))
                messages.Add(nameof(_enterpriseGroup.Name), new[] {"Stat unit doesn't have name"});

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_enterpriseGroup.ShortName))
                    messages.Add(nameof(_enterpriseGroup.ShortName), new[] {"Stat unit doesn't have short name"});
                else if (_enterpriseGroup.ShortName == _enterpriseGroup.Name)
                    messages.Add(nameof(_enterpriseGroup.ShortName), new[] {"Stat unit's short name is the same as name"});
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_enterpriseGroup.TelephoneNo))
                messages.Add(nameof(_enterpriseGroup.TelephoneNo), new[] {"Stat unit doesn't have telephone number"});

            if (_mandatoryFields.StatUnit.RegistrationReason && string.IsNullOrEmpty(_enterpriseGroup.RegistrationReason))
                messages.Add(nameof(_enterpriseGroup.RegistrationReason), new[] {"Stat unit doesn't have registration reason"});

            if (_mandatoryFields.StatUnit.ContactPerson && string.IsNullOrEmpty(_enterpriseGroup.ContactPerson))
                messages.Add(nameof(_enterpriseGroup.ContactPerson), new[] {"Stat unit doesn't have contact person"});

            return messages;
        }
    }
}
