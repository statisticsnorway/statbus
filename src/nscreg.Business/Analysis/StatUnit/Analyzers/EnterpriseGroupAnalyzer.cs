using System.Collections.Generic;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using System.Linq;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;

namespace nscreg.Business.Analysis.StatUnit.Analyzers
{
    public class EnterpriseGroupAnalyzer : BaseAnalyzer, IEnterpriseUnitAnalyzer
    {
        public EnterpriseGroupAnalyzer(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields) : base(
            analysisRules, mandatoryFields)
        {
        }

        public Dictionary<string, string[]> CheckOrphanUnits(IStatisticalUnit unit)
        {
            var manager = new OrphanManager(unit);
            var messages = new Dictionary<string, string[]>();
            (string key, string[] value) tuple;

            if (_analysisRules.Orphan.CheckRelatedEnterpriseGroup)
            {
                tuple = manager.CheckAssociatedEnterpriseGroup();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        public override Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit,
            List<IStatisticalUnit> units)
        {
            var messages = new Dictionary<string, string[]>();
            var checkedEnterpriseGroup = unit as EnterpriseGroup;

            foreach (var statUnit in units)
            {
                var enterpriseGroup = (EnterpriseGroup) statUnit;
                var unitMessages = new Dictionary<string, string[]>();
                var sameFieldsCount = 0;

                if (_analysisRules.Duplicates.CheckName && enterpriseGroup.Name == checkedEnterpriseGroup.Name &&
                    checkedEnterpriseGroup.Name != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.Name)))
                        unitMessages.Add(nameof(enterpriseGroup.Name), new[] {"Name field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckStatIdTaxRegId &&
                    (enterpriseGroup.StatId == checkedEnterpriseGroup.StatId &&
                     enterpriseGroup.TaxRegId == checkedEnterpriseGroup.TaxRegId) &&
                    checkedEnterpriseGroup.StatId != null && checkedEnterpriseGroup.TaxRegId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.StatId)))
                        unitMessages.Add(nameof(enterpriseGroup.StatId), new[] {"StatId field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckExternalId &&
                    enterpriseGroup.ExternalId == checkedEnterpriseGroup.ExternalId &&
                    checkedEnterpriseGroup.ExternalId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.ExternalId)))
                        unitMessages.Add(nameof(enterpriseGroup.ExternalId),
                            new[] {"ExternalId field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckShortName &&
                    enterpriseGroup.ShortName == checkedEnterpriseGroup.ShortName &&
                    checkedEnterpriseGroup.ShortName != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.ShortName)))
                        unitMessages.Add(nameof(enterpriseGroup.ShortName),
                            new[] {"ShortName field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckTelephoneNo &&
                    enterpriseGroup.TelephoneNo == checkedEnterpriseGroup.TelephoneNo &&
                    checkedEnterpriseGroup.TelephoneNo != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.TelephoneNo)))
                        unitMessages.Add(nameof(enterpriseGroup.TelephoneNo),
                            new[] {"TelephoneNo field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckAddressId &&
                    enterpriseGroup.AddressId == checkedEnterpriseGroup.AddressId &&
                    checkedEnterpriseGroup.AddressId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.AddressId)))
                        unitMessages.Add(nameof(enterpriseGroup.Address),
                            new[] {"Address field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckEmailAddress &&
                    enterpriseGroup.EmailAddress == checkedEnterpriseGroup.EmailAddress &&
                    checkedEnterpriseGroup.EmailAddress != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.EmailAddress)))
                        unitMessages.Add(nameof(enterpriseGroup.EmailAddress),
                            new[] {"EmailAddress field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckContactPerson &&
                    enterpriseGroup.ContactPerson == checkedEnterpriseGroup.ContactPerson &&
                    checkedEnterpriseGroup.ContactPerson != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(enterpriseGroup.ContactPerson)))
                        unitMessages.Add(nameof(enterpriseGroup.ContactPerson),
                            new[] {"ContactPerson field is duplicated"});
                }

                if (sameFieldsCount >= _analysisRules.Duplicates.MinimalIdenticalFieldsCount)
                    messages.AddRange(unitMessages);
            }

            return messages;
        }

        public override AnalysisResult CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses, List<IStatisticalUnit> units)
        {
            var baseAnalysisResult = base.CheckAll(unit, isAnyRelatedLegalUnit, isAnyRelatedActivities, addresses, units);
            var ophanUnitsResult = CheckOrphanUnits(unit);
            if (!ophanUnitsResult.Any()) return baseAnalysisResult;

            baseAnalysisResult.SummaryMessages.Add("Orphan units rules warnings");
            baseAnalysisResult.Messages.AddRange(ophanUnitsResult);

            return baseAnalysisResult;
        }
    }
}
