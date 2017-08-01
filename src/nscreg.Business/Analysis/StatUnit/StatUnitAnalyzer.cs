using System.Collections.Generic;
using System.Linq;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Business.Analysis.StatUnit
{
    /// <summary>
    /// Stat unit analyzer
    /// </summary>
    public class StatUnitAnalyzer : IStatUnitAnalyzer
    {
        private readonly Dictionary<StatUnitMandatoryFieldsEnum, bool> _mandatoryFieldsRules;
        private readonly Dictionary<StatUnitConnectionsEnum, bool> _connectionsRules;
        private readonly Dictionary<StatUnitOrphanEnum, bool> _orphanRules;

        public StatUnitAnalyzer(Dictionary<StatUnitMandatoryFieldsEnum, bool> mandatoryFieldsMandatoryFieldsRules,
            Dictionary<StatUnitConnectionsEnum, bool> connectionsRules, Dictionary<StatUnitOrphanEnum, bool> orphanRules)
        {
            _mandatoryFieldsRules = mandatoryFieldsMandatoryFieldsRules;
            _connectionsRules = connectionsRules;
            _orphanRules = orphanRules;
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

            if (unit.UnitType != StatUnitTypes.LegalUnit)
            {
                if (_connectionsRules.ContainsKey(StatUnitConnectionsEnum.CheckRelatedLegalUnit))
                    if (!isAnyRelatedLegalUnit)
                        messages.Add("LegalUnitId", new[] { "Stat unit doesn't have related legal unit" });

                if (_connectionsRules.ContainsKey(StatUnitConnectionsEnum.CheckRelatedActivities))
                    if (!isAnyRelatedActivities)
                        messages.Add("Activities", new[] { "Stat unit doesn't have related activity" });
            }

            if (_connectionsRules.ContainsKey(StatUnitConnectionsEnum.CheckAddress))
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

            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckDataSource))
            {
                tuple = manager.CheckDataSource();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckName))
            {
                tuple = manager.CheckName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckShortName))
            {
                tuple = manager.CheckShortName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckTelephoneNo))
            {
                tuple = manager.CheckTelephoneNo();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckRegistrationReason))
            {
                tuple = manager.CheckRegistrationReason();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckContactPerson))
            {
                tuple = manager.CheckContactPerson();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckStatus))
            {
                tuple = manager.CheckStatus();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckLegalUnitOwner))
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

            if (_orphanRules.ContainsKey(StatUnitOrphanEnum.CheckRelatedEnterpriseGroup))
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
            const int minIdenticalFieldsCount = 2;
            var statUnit = (StatisticalUnit) unit;
            var messages = new Dictionary<string, string[]>();

            foreach (var statisticalUnit in units)
            {
                var currentCount = 0;
                var unitMessages = new Dictionary<string, string[]>();

                if (statisticalUnit.Name == unit.Name && unit.Name != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.Name)))
                        unitMessages.Add(nameof(statisticalUnit.Name), new[] {"Name field is duplicated"});
                }

                if (statisticalUnit.StatId == statUnit.StatId && statisticalUnit.TaxRegId == statUnit.TaxRegId &&
                    unit.StatId != null && unit.TaxRegId != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.StatId)))
                        unitMessages.Add(nameof(statisticalUnit.StatId), new[] {"StatId field is duplicated"});
                }

                if (statisticalUnit.ExternalId == statUnit.ExternalId && unit.ExternalId != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.ExternalId)))
                        unitMessages.Add(nameof(statisticalUnit.ExternalId), new[] {"ExternalId field is duplicated"});
                }

                if (statisticalUnit.ShortName == statUnit.ShortName && statUnit.ShortName != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.ShortName)))
                        unitMessages.Add(nameof(statisticalUnit.ShortName), new[] {"ShortName field is duplicated"});
                }

                if (statisticalUnit.TelephoneNo == statUnit.TelephoneNo && statUnit.TelephoneNo != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.TelephoneNo)))
                        unitMessages.Add(nameof(statisticalUnit.TelephoneNo),
                            new[] {"TelephoneNo field is duplicated"});
                }

                if (statisticalUnit.AddressId == statUnit.AddressId && statUnit.AddressId != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.AddressId)))
                        unitMessages.Add(nameof(statisticalUnit.AddressId), new[] {"AddressId field is duplicated"});
                }

                if (statisticalUnit.EmailAddress == statUnit.EmailAddress && statUnit.EmailAddress != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.EmailAddress)))
                        unitMessages.Add(nameof(statisticalUnit.EmailAddress),
                            new[] {"EmailAddress field is duplicated"});
                }

                if (statisticalUnit.ContactPerson == statUnit.ContactPerson && statUnit.ContactPerson != null)
                {
                    currentCount++;
                    if (!messages.ContainsKey(nameof(statisticalUnit.ContactPerson)))
                        unitMessages.Add(nameof(statisticalUnit.ContactPerson),
                            new[] {"ContactPerson field is duplicated"});
                }

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

       
    }
}
