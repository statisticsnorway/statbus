using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;

namespace nscreg.Business.Analysis.StatUnit.Analyzers
{
    public class StatisticalUnitAnalyzer : BaseAnalyzer
    {
        public StatisticalUnitAnalyzer(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields) : base(
            analysisRules, mandatoryFields)
        {
        }

        public override Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit,
            List<IStatisticalUnit> units)
        {
            var messages = new Dictionary<string, string[]>();
            var checkedStatisticalUnit = unit as StatisticalUnit;

            foreach (var statUnit in units)
            {
                var statisticalUnit = (StatisticalUnit) statUnit;
                var unitMessages = new Dictionary<string, string[]>();
                var sameFieldsCount = 0;

                if (_analysisRules.Duplicates.CheckName && statisticalUnit.Name == checkedStatisticalUnit.Name &&
                    checkedStatisticalUnit.Name != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.Name)))
                        unitMessages.Add(nameof(statisticalUnit.Name), new[] {"Name field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckStatIdTaxRegId &&
                    (statisticalUnit.StatId == checkedStatisticalUnit.StatId &&
                     statisticalUnit.TaxRegId == checkedStatisticalUnit.TaxRegId) &&
                    checkedStatisticalUnit.StatId != null && checkedStatisticalUnit.TaxRegId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.StatId)))
                        unitMessages.Add(nameof(statisticalUnit.StatId), new[] {"StatId field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckExternalId &&
                    statisticalUnit.ExternalId == checkedStatisticalUnit.ExternalId &&
                    checkedStatisticalUnit.ExternalId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.ExternalId)))
                        unitMessages.Add(nameof(statisticalUnit.ExternalId),
                            new[] {"ExternalId field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckShortName &&
                    statisticalUnit.ShortName == checkedStatisticalUnit.ShortName &&
                    checkedStatisticalUnit.ShortName != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.ShortName)))
                        unitMessages.Add(nameof(statisticalUnit.ShortName),
                            new[] {"ShortName field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckTelephoneNo &&
                    statisticalUnit.TelephoneNo == checkedStatisticalUnit.TelephoneNo &&
                    checkedStatisticalUnit.TelephoneNo != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.TelephoneNo)))
                        unitMessages.Add(nameof(statisticalUnit.TelephoneNo),
                            new[] {"TelephoneNo field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckAddressId &&
                    statisticalUnit.AddressId == checkedStatisticalUnit.AddressId &&
                    checkedStatisticalUnit.AddressId != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.AddressId)))
                        unitMessages.Add(nameof(statisticalUnit.Address),
                            new[] {"Address field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckEmailAddress &&
                    statisticalUnit.EmailAddress == checkedStatisticalUnit.EmailAddress &&
                    checkedStatisticalUnit.EmailAddress != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.EmailAddress)))
                        unitMessages.Add(nameof(statisticalUnit.EmailAddress),
                            new[] {"EmailAddress field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckContactPerson &&
                    statisticalUnit.ContactPerson == checkedStatisticalUnit.ContactPerson &&
                    checkedStatisticalUnit.ContactPerson != null)
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.ContactPerson)))
                        unitMessages.Add(nameof(statisticalUnit.ContactPerson),
                            new[] {"ContactPerson field is duplicated"});
                }

                if (_analysisRules.Duplicates.CheckOwnerPerson &&
                    statisticalUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) ==
                    checkedStatisticalUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner))
                {
                    sameFieldsCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.PersonsUnits)))
                        unitMessages.Add(nameof(statisticalUnit.Persons),
                            new[] {"Stat checkedStatisticalUnit owner person is duplicated"});
                }

                if (sameFieldsCount >= _analysisRules.Duplicates.MinimalIdenticalFieldsCount)
                    messages.AddRange(unitMessages);
            }

            return messages;
        }
    }
}
