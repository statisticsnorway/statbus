using System;
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
            var key = string.Empty;
            var value = Array.Empty<string>();

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
                manager.CheckAddress(addresses, ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
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
            var key = string.Empty;
            var value = Array.Empty<string>();

            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckDataSource))
            {
                manager.CheckDataSource(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckName))
            {
                manager.CheckName(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckShortName))
            {
                manager.CheckShortName(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckTelephoneNo))
            {
                manager.CheckTelephoneNo(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckRegistrationReason))
            {
                manager.CheckRegistrationReason(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckContactPerson))
            {
                manager.CheckContactPerson(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckStatus))
            {
                manager.CheckStatus(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }
            if (_mandatoryFieldsRules.ContainsKey(StatUnitMandatoryFieldsEnum.CheckLegalUnitOwner))
            {
                manager.CheckLegalUnitOwner(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }

            return messages;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckOrphanUnits"/>
        /// </summary>
        public Dictionary<string, string[]> CheckOrphanUnits(IStatisticalUnit unit)
        {
            var manager = new OrphanManager(unit);
            var key = string.Empty;
            var value = Array.Empty<string>();
            var messages = new Dictionary<string, string[]>();

            if (_orphanRules.ContainsKey(StatUnitOrphanEnum.CheckRelatedEnterpriseGroup))
            {
                manager.CheckAssociatedEnterpriseGroup(ref key, ref value);
                if (key != string.Empty)
                {
                    messages.Add(key, value);
                    key = string.Empty;
                    value = Array.Empty<string>();
                }
            }

            return messages;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckAll"/>
        /// </summary>
        public Dictionary<int, Dictionary<string, string[]>> CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses)
        {
            var messages = new Dictionary<string, string[]>();
           
            messages.AddRange(CheckConnections(unit, isAnyRelatedLegalUnit, isAnyRelatedActivities, addresses));
            messages.AddRange(CheckMandatoryFields(unit));
           
            if (unit.UnitType == StatUnitTypes.EnterpriseUnit)
                messages.AddRange(CheckOrphanUnits(unit));

            var result = new Dictionary<int, Dictionary<string, string[]>>
            {
                { unit.RegId, messages }
            };
            return result;
        }

        public List<IStatisticalUnit> CheckDuplicates(IStatisticalUnit unit, List<StatisticalUnit> units)
        {
            const int minIdenticalFieldsCount = 2;
            var statUnit = (StatisticalUnit)unit;
            var duplicates = new List<IStatisticalUnit>();

            foreach (var statisticalUnit in units)
            {
                var currentCount = 0;

                if (statisticalUnit.Name == unit.Name) currentCount++;

                if (statisticalUnit.StatId == statUnit.StatId && statisticalUnit.TaxRegId == statUnit.TaxRegId) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.ExternalId == statUnit.ExternalId) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.ShortName == statUnit.ShortName) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.TelephoneNo == statUnit.TelephoneNo) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.AddressId == statUnit.AddressId) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.EmailAddress == statUnit.EmailAddress) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.ContactPerson == statUnit.ContactPerson) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;

                if (statisticalUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) ==
                    statUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner)) currentCount++;
                if (IdenticalFieldsCountMoreThen(currentCount, statisticalUnit)) continue;
            }

            bool IdenticalFieldsCountMoreThen(int count, IStatisticalUnit statisticalUnit)
            {
                if (count <= minIdenticalFieldsCount) return false;
                duplicates.Add(statisticalUnit);
                return true;
            }

            return duplicates;
        }
    }
}
