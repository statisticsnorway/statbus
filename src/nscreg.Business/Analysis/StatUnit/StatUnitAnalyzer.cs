using System.Collections.Generic;
using System.Linq;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

// ReSharper disable TooWideLocalVariableScope

namespace nscreg.Business.Analysis.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Stat unit analyzer
    /// </summary>
    public class StatUnitAnalyzer : IStatUnitAnalyzer
    {
        private readonly Connections _connections;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly Orphan _orphan;
        private readonly Duplicates _duplicates;

        public StatUnitAnalyzer(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields)
        {
            _connections = analysisRules.Connections;
            _mandatoryFields = mandatoryFields;
            _orphan = analysisRules.Orphan;
            _duplicates = analysisRules.Duplicates;
        }

        /// <inheritdoc />
        /// <summary>
        /// <see cref="M:nscreg.Business.Analysis.StatUnit.IStatUnitAnalyzer.CheckConnections(nscreg.Data.Entities.IStatisticalUnit,System.Boolean,System.Boolean,System.Collections.Generic.List{nscreg.Data.Entities.Address})" />
        /// </summary>
        public Dictionary<string, string[]> CheckConnections(IStatisticalUnit unit,
            bool isAnyRelatedLegalUnit, bool isAnyRelatedActivities, List<Address> addresses)
        {
            var messages = new Dictionary<string, string[]>();
            var manager = new ConnectionsManager(unit);
            (string key, string[] value) tuple;
            
            if (_connections.CheckRelatedLegalUnit)
                if (!isAnyRelatedLegalUnit)
                    messages.Add(unit is LocalUnit ? nameof(LocalUnit.LegalUnitId) : nameof(EnterpriseUnit.LegalUnits),
                        new[] {"Stat unit doesn't have related legal unit"});

            if(_connections.CheckRelatedActivities)
                if (!isAnyRelatedActivities)
                    messages.Add(nameof(StatisticalUnit.Activities), new[] { "Stat unit doesn't have related activity" });

            if (_connections.CheckAddress)
            {
                tuple = manager.CheckAddress(addresses);
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        /// <inheritdoc />
        /// <summary>
        /// <see cref="M:nscreg.Business.Analysis.StatUnit.IStatUnitAnalyzer.CheckMandatoryFields(nscreg.Data.Entities.IStatisticalUnit)" />
        /// </summary>
        public Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();
            var manager = new MandatoryFieldsManager(unit);
            (string key, string[] value) tuple;
            
            if (_mandatoryFields.StatUnit.DataSource)
            {
                tuple = manager.CheckDataSource();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.Name)
            {
                tuple = manager.CheckName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.ShortName)
            {
                tuple = manager.CheckShortName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.TelephoneNo)
            {
                tuple = manager.CheckTelephoneNo();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.RegistrationReason)
            {
                tuple = manager.CheckRegistrationReason();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.ContactPerson)
            {
                tuple = manager.CheckContactPerson();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.Status)
            {
                tuple = manager.CheckStatus();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.LegalUnit.Owner)
            {
                tuple = manager.CheckLegalUnitOwner();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        /// <inheritdoc />
        /// <summary>
        /// <see cref="M:nscreg.Business.Analysis.StatUnit.IStatUnitAnalyzer.CheckOrphanUnits(nscreg.Data.Entities.IStatisticalUnit)" />
        /// </summary>
        public Dictionary<string, string[]> CheckOrphanUnits(IStatisticalUnit unit)
        {
            var manager = new OrphanManager(unit);
            var messages = new Dictionary<string, string[]>();
            (string key, string[] value) tuple;

            if (_orphan.CheckRelatedEnterpriseGroup)
            {
                tuple = manager.CheckAssociatedEnterpriseGroup();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        /// <inheritdoc />
        /// <summary>
        /// <see cref="M:nscreg.Business.Analysis.StatUnit.IStatUnitAnalyzer.CheckDuplicates(nscreg.Data.Entities.IStatisticalUnit,System.Collections.Generic.List{nscreg.Data.Entities.StatisticalUnit})" />
        /// </summary>
        public Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<IStatisticalUnit> units)
        {
            var messages = new Dictionary<string, string[]>();
            if (!units.Any()) return messages;

            var statUnit = unit as StatisticalUnit;
            var entGroup = unit as EnterpriseGroup;

            if (statUnit != null)
                foreach (var statisticalUnit in units)
                {
                    var currentCount = 0;
                    var unitMessages = new Dictionary<string, string[]>();

                    unitMessages.AddRange(StatisticalUnitChecks(statisticalUnit as StatisticalUnit, statUnit, messages,
                        ref currentCount));

                    if (currentCount >= _duplicates.MinimalIdenticalFieldsCount)
                        messages.AddRange(unitMessages);
                }
            else
            {
                foreach (var statisticalUnit in units)
                {
                    var currentCount = 0;
                    var unitMessages = new Dictionary<string, string[]>();

                    unitMessages.AddRange(EnterpriseGroupChecks(statisticalUnit as EnterpriseGroup, entGroup, messages,
                        ref currentCount));

                    if (currentCount >= _duplicates.MinimalIdenticalFieldsCount)
                        messages.AddRange(unitMessages);
                }
            }
            
            return messages;
        }

        private Dictionary<string, string[]> StatisticalUnitChecks(StatisticalUnit dataBaseUnit, StatisticalUnit updatedUnit,
            IReadOnlyDictionary<string, string[]> messages, ref int currentCount)
        {
            var unitMessages = new Dictionary<string, string[]>();

            if (_duplicates.CheckName && dataBaseUnit.Name == updatedUnit.Name && updatedUnit.Name != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.Name)))
                    unitMessages.Add(nameof(dataBaseUnit.Name), new[] { "Name field is duplicated" });
            }

            if (_duplicates.CheckStatIdTaxRegId &&
                (dataBaseUnit.StatId == updatedUnit.StatId && dataBaseUnit.TaxRegId == updatedUnit.TaxRegId) &&
                updatedUnit.StatId != null && updatedUnit.TaxRegId != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.StatId)))
                    unitMessages.Add(nameof(dataBaseUnit.StatId), new[] { "StatId field is duplicated" });
            }

            if (_duplicates.CheckExternalId && dataBaseUnit.ExternalId == updatedUnit.ExternalId &&
                updatedUnit.ExternalId != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.ExternalId)))
                    unitMessages.Add(nameof(dataBaseUnit.ExternalId),
                        new[] { "ExternalId field is duplicated" });
            }

            if (_duplicates.CheckShortName && dataBaseUnit.ShortName == updatedUnit.ShortName &&
                updatedUnit.ShortName != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.ShortName)))
                    unitMessages.Add(nameof(dataBaseUnit.ShortName),
                        new[] {"ShortName field is duplicated"});
            }

            if (_duplicates.CheckTelephoneNo && dataBaseUnit.TelephoneNo == updatedUnit.TelephoneNo &&
                updatedUnit.TelephoneNo != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.TelephoneNo)))
                    unitMessages.Add(nameof(dataBaseUnit.TelephoneNo),
                        new[] {"TelephoneNo field is duplicated"});
            }

            if (_duplicates.CheckAddressId && dataBaseUnit.AddressId == updatedUnit.AddressId &&
                updatedUnit.AddressId != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.AddressId)))
                    unitMessages.Add(nameof(dataBaseUnit.Address),
                        new[] {"Address field is duplicated"});
            }

            if (_duplicates.CheckEmailAddress && dataBaseUnit.EmailAddress == updatedUnit.EmailAddress &&
                updatedUnit.EmailAddress != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.EmailAddress)))
                    unitMessages.Add(nameof(dataBaseUnit.EmailAddress),
                        new[] {"EmailAddress field is duplicated"});
            }

            if (_duplicates.CheckContactPerson && dataBaseUnit.ContactPerson == updatedUnit.ContactPerson &&
                updatedUnit.ContactPerson != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.ContactPerson)))
                    unitMessages.Add(nameof(dataBaseUnit.ContactPerson),
                        new[] {"ContactPerson field is duplicated"});
            }

            if (_duplicates.CheckOwnerPerson &&
                dataBaseUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) ==
                updatedUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner))
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.PersonsUnits)))
                    unitMessages.Add(nameof(dataBaseUnit.Persons),
                        new[] {"Stat unit owner person is duplicated"});
            }

            return unitMessages;
        }

        private Dictionary<string, string[]> EnterpriseGroupChecks(EnterpriseGroup dataBaseUnit, EnterpriseGroup updatedUnit,
           IReadOnlyDictionary<string, string[]> messages, ref int currentCount)
        {
            var unitMessages = new Dictionary<string, string[]>();

            if (_duplicates.CheckName && dataBaseUnit.Name == updatedUnit.Name && updatedUnit.Name != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.Name)))
                    unitMessages.Add(nameof(dataBaseUnit.Name), new[] { "Name field is duplicated" });
            }

            if (_duplicates.CheckStatIdTaxRegId &&
                (dataBaseUnit.StatId == updatedUnit.StatId && dataBaseUnit.TaxRegId == updatedUnit.TaxRegId) &&
                updatedUnit.StatId != null && updatedUnit.TaxRegId != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.StatId)))
                    unitMessages.Add(nameof(dataBaseUnit.StatId), new[] { "StatId field is duplicated" });
            }

            if (_duplicates.CheckExternalId && dataBaseUnit.ExternalId == updatedUnit.ExternalId &&
                updatedUnit.ExternalId != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.ExternalId)))
                    unitMessages.Add(nameof(dataBaseUnit.ExternalId),
                        new[] { "ExternalId field is duplicated" });
            }

            if (_duplicates.CheckShortName && dataBaseUnit.ShortName == updatedUnit.ShortName &&
                updatedUnit.ShortName != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.ShortName)))
                    unitMessages.Add(nameof(dataBaseUnit.ShortName),
                        new[] { "ShortName field is duplicated" });
            }

            if (_duplicates.CheckTelephoneNo && dataBaseUnit.TelephoneNo == updatedUnit.TelephoneNo &&
                updatedUnit.TelephoneNo != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.TelephoneNo)))
                    unitMessages.Add(nameof(dataBaseUnit.TelephoneNo),
                        new[] { "TelephoneNo field is duplicated" });
            }

            if (_duplicates.CheckAddressId && dataBaseUnit.AddressId == updatedUnit.AddressId &&
                updatedUnit.AddressId != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.AddressId)))
                    unitMessages.Add(nameof(dataBaseUnit.Address),
                        new[] { "Address field is duplicated" });
            }

            if (_duplicates.CheckEmailAddress && dataBaseUnit.EmailAddress == updatedUnit.EmailAddress &&
                updatedUnit.EmailAddress != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.EmailAddress)))
                    unitMessages.Add(nameof(dataBaseUnit.EmailAddress),
                        new[] { "EmailAddress field is duplicated" });
            }

            if (_duplicates.CheckContactPerson && dataBaseUnit.ContactPerson == updatedUnit.ContactPerson &&
                updatedUnit.ContactPerson != null)
            {
                currentCount++;
                if (!messages.ContainsKey(nameof(dataBaseUnit.ContactPerson)))
                    unitMessages.Add(nameof(dataBaseUnit.ContactPerson),
                        new[] { "ContactPerson field is duplicated" });
            }

            return unitMessages;
        }

        /// <inheritdoc />
        /// <summary>
        /// <see cref="M:nscreg.Business.Analysis.StatUnit.IStatUnitAnalyzer.CheckAll(nscreg.Data.Entities.IStatisticalUnit,System.Boolean,System.Boolean,System.Collections.Generic.List{nscreg.Data.Entities.Address},System.Collections.Generic.List{nscreg.Data.Entities.StatisticalUnit})" />
        /// </summary>
        public AnalysisResult CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses, List<IStatisticalUnit> units)
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
