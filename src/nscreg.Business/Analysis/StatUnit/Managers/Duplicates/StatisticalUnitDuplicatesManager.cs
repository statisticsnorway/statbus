using nscreg.Business.Analysis.Contracts;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using System.Collections.Generic;

namespace nscreg.Business.Analysis.StatUnit.Managers.Duplicates
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis statistical unit duplicates manager
    /// </summary>
    public class StatisticalUnitDuplicatesManager : IAnalysisManager
    {
        private readonly History _checkingHistory;
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly List<AnalysisDuplicateResult> _potentialDuplicates;

        public StatisticalUnitDuplicatesManager(History enterpriseGroup, StatUnitAnalysisRules analysisRules,
            List<AnalysisDuplicateResult> potentialDuplicates)
        {
            _checkingHistory = enterpriseGroup;
            _analysisRules = analysisRules;
            _potentialDuplicates = potentialDuplicates;
        }

        /// <summary>
        /// Check fields for duplicate
        /// </summary>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckFields()
        {
            var messages = new Dictionary<string, string[]>();

            foreach (var potentialDuplicate in _potentialDuplicates)
            {
                var unitMessages = new Dictionary<string, string[]>();
                var sameFieldsCount = 0;

                if (_analysisRules.Duplicates.CheckName && potentialDuplicate.Name == _checkingHistory.Name &&
                    _checkingHistory.Name != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.Name)))
                        unitMessages.Add(nameof(potentialDuplicate.Name),
                            new[] { nameof(Resource.AnalysisDuplicationName) });
                }

                if (_analysisRules.Duplicates.CheckStatId &&
                    potentialDuplicate.StatId == _checkingHistory.StatId && _checkingHistory.StatId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.StatId)))
                        unitMessages.Add(nameof(potentialDuplicate.StatId),
                            new[] { nameof(Resource.AnalysisDuplicationStatId) });
                }

                if (_analysisRules.Duplicates.CheckTaxRegId &&
                    potentialDuplicate.TaxRegId == _checkingHistory.TaxRegId && _checkingHistory.TaxRegId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.TaxRegId)))
                        unitMessages.Add(nameof(potentialDuplicate.TaxRegId),
                            new[] { nameof(Resource.AnalysisDuplicationTaxRegId) });
                }

                if (_analysisRules.Duplicates.CheckExternalId &&
                    potentialDuplicate.ExternalId == _checkingHistory.ExternalId &&
                    _checkingHistory.ExternalId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.ExternalId)))
                        unitMessages.Add(nameof(potentialDuplicate.ExternalId),
                            new[] { nameof(Resource.AnalysisDuplicationExternalId) });
                }

                if (_analysisRules.Duplicates.CheckShortName &&
                    potentialDuplicate.ShortName == _checkingHistory.ShortName &&
                    _checkingHistory.ShortName != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.ShortName)))
                        unitMessages.Add(nameof(potentialDuplicate.ShortName),
                            new[] { nameof(Resource.AnalysisDuplicationShortName) });
                }

                if (_analysisRules.Duplicates.CheckTelephoneNo &&
                    potentialDuplicate.TelephoneNo == _checkingHistory.TelephoneNo &&
                    _checkingHistory.TelephoneNo != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.TelephoneNo)))
                        unitMessages.Add(nameof(potentialDuplicate.TelephoneNo),
                            new[] { nameof(Resource.AnalysisDuplicationTelephoneNo) });
                }

                if (_analysisRules.Duplicates.CheckAddressId &&
                    potentialDuplicate.AddressId == _checkingHistory.AddressId &&
                    _checkingHistory.AddressId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.AddressId)))
                        unitMessages.Add(nameof(potentialDuplicate.Address),
                            new[] { nameof(Resource.AnalysisDuplicationAddress) });
                }

                if (_analysisRules.Duplicates.CheckEmailAddress &&
                    potentialDuplicate.EmailAddress == _checkingHistory.EmailAddress &&
                    _checkingHistory.EmailAddress != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.EmailAddress)))
                        unitMessages.Add(nameof(potentialDuplicate.EmailAddress),
                            new[] { nameof(Resource.AnalysisDuplicationEmailAddress) });
                }

                if (sameFieldsCount >= _analysisRules.Duplicates.MinimalIdenticalFieldsCount)
                    messages.AddRange(unitMessages);
            }

            return messages;
        }
    }
}
