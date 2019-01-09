using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using nscreg.Business.Analysis.Contracts;
using nscreg.Resources.Languages;

namespace nscreg.Business.Analysis.StatUnit.Managers.Duplicates
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis statistical unit duplicates manager
    /// </summary>
    public class StatisticalUnitDuplicatesManager : IAnalysisManager
    {
        private readonly StatisticalUnit _checkingStatisticalUnit;
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly List<IStatisticalUnit> _potentialDuplicates;

        public StatisticalUnitDuplicatesManager(StatisticalUnit enterpriseGroup, StatUnitAnalysisRules analysisRules,
            List<IStatisticalUnit> potentialDuplicates)
        {
            _checkingStatisticalUnit = enterpriseGroup;
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

            foreach (var unit in _potentialDuplicates)
            {
                var potentialDuplicate = unit as StatisticalUnit;
                var unitMessages = new Dictionary<string, string[]>();
                var sameFieldsCount = 0;

                if (_analysisRules.Duplicates.CheckName && potentialDuplicate.Name == _checkingStatisticalUnit.Name &&
                    _checkingStatisticalUnit.Name != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.Name)))
                        unitMessages.Add(nameof(potentialDuplicate.Name),
                            new[] { nameof(Resource.AnalysisDuplicationName) });
                }

                if (_analysisRules.Duplicates.CheckStatIdTaxRegId &&
                    (potentialDuplicate.StatId == _checkingStatisticalUnit.StatId &&
                     potentialDuplicate.TaxRegId == _checkingStatisticalUnit.TaxRegId) &&
                    _checkingStatisticalUnit.StatId != null && _checkingStatisticalUnit.TaxRegId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.StatId)))
                        unitMessages.Add(nameof(potentialDuplicate.StatId),
                            new[] { nameof(Resource.AnalysisDuplicationStatId) });
                }

                if (_analysisRules.Duplicates.CheckExternalId &&
                    potentialDuplicate.ExternalId == _checkingStatisticalUnit.ExternalId &&
                    _checkingStatisticalUnit.ExternalId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.ExternalId)))
                        unitMessages.Add(nameof(potentialDuplicate.ExternalId),
                            new[] { nameof(Resource.AnalysisDuplicationExternalId) });
                }

                if (_analysisRules.Duplicates.CheckShortName &&
                    potentialDuplicate.ShortName == _checkingStatisticalUnit.ShortName &&
                    _checkingStatisticalUnit.ShortName != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.ShortName)))
                        unitMessages.Add(nameof(potentialDuplicate.ShortName),
                            new[] { nameof(Resource.AnalysisDuplicationShortName) });
                }

                if (_analysisRules.Duplicates.CheckTelephoneNo &&
                    potentialDuplicate.TelephoneNo == _checkingStatisticalUnit.TelephoneNo &&
                    _checkingStatisticalUnit.TelephoneNo != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.TelephoneNo)))
                        unitMessages.Add(nameof(potentialDuplicate.TelephoneNo),
                            new[] { nameof(Resource.AnalysisDuplicationTelephoneNo) });
                }

                if (_analysisRules.Duplicates.CheckAddressId &&
                    potentialDuplicate.AddressId == _checkingStatisticalUnit.AddressId &&
                    _checkingStatisticalUnit.AddressId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.AddressId)))
                        unitMessages.Add(nameof(potentialDuplicate.Address),
                            new[] { nameof(Resource.AnalysisDuplicationAddress) });
                }

                if (_analysisRules.Duplicates.CheckEmailAddress &&
                    potentialDuplicate.EmailAddress == _checkingStatisticalUnit.EmailAddress &&
                    _checkingStatisticalUnit.EmailAddress != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(potentialDuplicate.EmailAddress)))
                        unitMessages.Add(nameof(potentialDuplicate.EmailAddress),
                            new[] { nameof(Resource.AnalysisDuplicationEmailAddress) });
                }

                if (_analysisRules.Duplicates.CheckContactPerson && potentialDuplicate.PersonsUnits.Any() &&
                    potentialDuplicate.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.ContactPerson) ==
                    _checkingStatisticalUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.ContactPerson))
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey("Contact" + nameof(potentialDuplicate.Persons)))
                        unitMessages.Add("Contact" + nameof(potentialDuplicate.Persons),
                            new[] { nameof(Resource.AnalysisDuplicationContactPerson) });
                }

                if (_analysisRules.Duplicates.CheckOwnerPerson && potentialDuplicate.PersonsUnits.Any() &&
                    potentialDuplicate.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) ==
                    _checkingStatisticalUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner))
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey("Owner" + nameof(potentialDuplicate.Persons)))
                        unitMessages.Add("Owner" + nameof(potentialDuplicate.Persons),
                            new[] { nameof(Resource.AnalysisDuplicationOwnerPerson) });
                }

                if (sameFieldsCount >= _analysisRules.Duplicates.MinimalIdenticalFieldsCount)
                    messages.AddRange(unitMessages);
            }

            return messages;
        }
    }
}
