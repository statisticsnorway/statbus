using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.Configuration;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
// ReSharper disable TooWideLocalVariableScope

namespace nscreg.Business.Analysis.StatUnit
{
    /// <summary>
    /// Stat unit analyzer
    /// </summary>
    public class StatUnitAnalyzer : IStatUnitAnalyzer
    {
        private readonly StatUnitAnalysisRules _analysisRules;

        public StatUnitAnalyzer(StatUnitAnalysisRules analysisRules)
        {
            _analysisRules = analysisRules;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckConnections"/>
        /// </summary>
        public Dictionary<string, string[]> CheckConnections(IStatisticalUnit unit,
            bool isAnyRelatedLegalUnit, bool isAnyRelatedActivities, List<Address> addresses)
        {
            var messages = new Dictionary<string, string[]>();
            var manager = new ConnectionsManager(unit);
            (string key, string[] value) tuple;
            
            if (CheckRule(_analysisRules.ConnectionsRules, nameof(StatUnitConnectionsEnum.CheckRelatedLegalUnit)))
                if (!isAnyRelatedLegalUnit)
                    messages.Add("LegalUnitId", new[] {"Stat unit doesn't have related legal unit"});

            if(CheckRule(_analysisRules.ConnectionsRules, nameof(StatUnitConnectionsEnum.CheckRelatedActivities)))
                if (!isAnyRelatedActivities)
                    messages.Add("Activities", new[] { "Stat unit doesn't have related activity" });

            if (CheckRule(_analysisRules.ConnectionsRules, nameof(StatUnitConnectionsEnum.CheckAddress)))
            {
                tuple = manager.CheckAddress(addresses);
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckMandatoryFields"/>
        /// </summary>
        public Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();
            var manager = new MandatoryFieldsManager(unit);
            (string key, string[] value) tuple;
            
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckDataSource)))
            {
                tuple = manager.CheckDataSource();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckName)))
            {
                tuple = manager.CheckName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckShortName)))
            {
                tuple = manager.CheckShortName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckTelephoneNo)))
            {
                tuple = manager.CheckTelephoneNo();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckRegistrationReason)))
            {
                tuple = manager.CheckRegistrationReason();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckContactPerson)))
            {
                tuple = manager.CheckContactPerson();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckStatus)))
            {
                tuple = manager.CheckStatus();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (CheckRule(_analysisRules.MandatoryFieldsRules, nameof(StatUnitMandatoryFieldsEnum.CheckLegalUnitOwner)))
            {
                tuple = manager.CheckLegalUnitOwner();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckOrphanUnits"/>
        /// </summary>
        public Dictionary<string, string[]> CheckOrphanUnits(IStatisticalUnit unit)
        {
            var manager = new OrphanManager(unit);
            var messages = new Dictionary<string, string[]>();
            (string key, string[] value) tuple;

            if (CheckRule(_analysisRules.OphanRules, nameof(StatUnitOrphanEnum.CheckRelatedEnterpriseGroup)))
            {
                tuple = manager.CheckAssociatedEnterpriseGroup();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckDuplicates"/>
        /// </summary>
        public Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<StatisticalUnit> units)
        {
            var messages = new Dictionary<string, string[]>();
            if (!units.Any()) return messages;

            var statUnit = (StatisticalUnit) unit;
            if (!int.TryParse(_analysisRules.DuplicatesRules["MinimalIdenticalFieldsCount"], out int minIdenticalFieldsCount))
                minIdenticalFieldsCount = 2;

            foreach (var statisticalUnit in units)
            {
                var currentCount = 0;
                var unitMessages = new Dictionary<string, string[]>();

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckName)))
                    if (statisticalUnit.Name == unit.Name && unit.Name != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.Name)))
                            unitMessages.Add(nameof(statisticalUnit.Name), new[] {"Name field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckStatIdTaxRegId)))
                    if (statisticalUnit.StatId == statUnit.StatId && statisticalUnit.TaxRegId == statUnit.TaxRegId &&
                        unit.StatId != null && unit.TaxRegId != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.StatId)))
                            unitMessages.Add(nameof(statisticalUnit.StatId), new[] {"StatId field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckExternalId)))
                    if (statisticalUnit.ExternalId == statUnit.ExternalId && unit.ExternalId != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.ExternalId)))
                            unitMessages.Add(nameof(statisticalUnit.ExternalId),
                                new[] {"ExternalId field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckShortName)))
                    if (statisticalUnit.ShortName == statUnit.ShortName && statUnit.ShortName != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.ShortName)))
                            unitMessages.Add(nameof(statisticalUnit.ShortName),
                                new[] {"ShortName field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckTelephoneNo)))
                    if (statisticalUnit.TelephoneNo == statUnit.TelephoneNo && statUnit.TelephoneNo != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.TelephoneNo)))
                            unitMessages.Add(nameof(statisticalUnit.TelephoneNo),
                                new[] {"TelephoneNo field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckAddressId)))
                    if (statisticalUnit.AddressId == statUnit.AddressId && statUnit.AddressId != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.AddressId)))
                            unitMessages.Add(nameof(statisticalUnit.AddressId),
                                new[] {"AddressId field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckEmailAddress)))
                    if (statisticalUnit.EmailAddress == statUnit.EmailAddress && statUnit.EmailAddress != null)
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.EmailAddress)))
                            unitMessages.Add(nameof(statisticalUnit.EmailAddress),
                                new[] {"EmailAddress field is duplicated"});
                    }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckContactPerson)))
                    if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckEmailAddress)))
                        if (statisticalUnit.ContactPerson == statUnit.ContactPerson && statUnit.ContactPerson != null)
                        {
                            currentCount++;
                            if (!messages.ContainsKey(nameof(statisticalUnit.ContactPerson)))
                                unitMessages.Add(nameof(statisticalUnit.ContactPerson),
                                    new[] {"ContactPerson field is duplicated"});
                        }

                if (CheckRule(_analysisRules.DuplicatesRules, nameof(StatUnitDuplicatesEnum.CheckOwnerPerson)))
                    if (statisticalUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) ==
                        statUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner))
                    {
                        currentCount++;
                        if (!messages.ContainsKey(nameof(statisticalUnit.PersonsUnits)))
                            unitMessages.Add(nameof(statisticalUnit.PersonsUnits),
                                new[] {"Stat unit owner person is duplicated"});
                    }

                if (currentCount >= minIdenticalFieldsCount)
                    messages.AddRange(unitMessages);
            }

            return messages;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckAll"/>
        /// </summary>
        public AnalysisResult CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses, List<StatisticalUnit> units)
        {
            var messages = new Dictionary<string, string[]>();
            var summaryMessages = new List<string>();

            var connectionsResult = CheckConnections(unit, isAnyRelatedLegalUnit, isAnyRelatedActivities, addresses);
            if (connectionsResult.Any())
            {
                summaryMessages.Add("Connection rules warnings");
                messages.AddRange(connectionsResult);
            }

            var mandatoryFieldsResult = CheckMandatoryFields(unit);
            if (mandatoryFieldsResult.Any())
            {
                summaryMessages.Add("Mandatory fields rules warnings");
                messages.AddRange(mandatoryFieldsResult);
            }

            if (unit.UnitType == StatUnitTypes.EnterpriseUnit)
            {
                var ophanUnitsResult = CheckOrphanUnits(unit);
                if (ophanUnitsResult.Any())
                {
                    summaryMessages.Add("Orphan units rules warnings");
                    messages.AddRange(ophanUnitsResult);
                }
            }

            var duplicatesResult = CheckDuplicates(unit, units);
            if (duplicatesResult.Any())
            {
                summaryMessages.Add("Duplicate fields rules warnings");

                duplicatesResult.ForEach(d =>
                {
                    if (messages.ContainsKey(d.Key))
                    {
                        var existed = messages[d.Key];
                        messages[d.Key] = existed.Concat(d.Value).ToArray();
                    }
                    else
                        messages.Add(d.Key, d.Value);
                });
            }

            return new AnalysisResult
            {
                Name = unit.Name,
                Type = unit.UnitType,
                Messages = messages,
                SummaryMessages = summaryMessages
            };
        }

        private static bool CheckRule(IConfiguration configuration, string keyName)
        {
            return configuration.GetChildren().FirstOrDefault(c => c.Key == keyName).Value == "True";
        }
    }
}