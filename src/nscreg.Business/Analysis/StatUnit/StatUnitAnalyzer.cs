using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Business.Analysis.Contracts;
using nscreg.Business.Analysis.StatUnit.Managers;
using nscreg.Business.Analysis.StatUnit.Managers.Duplicates;
using nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Data.Constants;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using Microsoft.EntityFrameworkCore;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Business.Analysis.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Stat unit analyzer
    /// </summary>
    public class StatUnitAnalyzer : IStatUnitAnalyzer
    {
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly NSCRegDbContext _context;

        public StatUnitAnalyzer(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields, NSCRegDbContext context)
        {
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
            _context = context;
        }
        
        public Dictionary<string, string[]> CheckConnections(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();

            if (_analysisRules.Connections.CheckRelatedLegalUnit)
            {
                var hasRelatedLegalUnit = unit is LocalUnit localUnit
                    ? localUnit.LegalUnitId != null
                    : !(unit is EnterpriseUnit) || ((EnterpriseUnit) unit).LegalUnits.Any();

                if (!hasRelatedLegalUnit)
                    messages.Add(unit is LocalUnit ? nameof(LocalUnit.LegalUnitId) : nameof(EnterpriseUnit.LegalUnits),
                        new[] {"Stat unit doesn't have related legal unit(s)"});
            }

            if (_analysisRules.Connections.CheckRelatedActivities)
            {
                var hasRelatedActivities = !(unit is LocalUnit) && !(unit is EnterpriseUnit) ||
                                           ((StatisticalUnit) unit).ActivitiesUnits.Any();
                if (!hasRelatedActivities)
                    messages.Add(nameof(StatisticalUnit.Activities), new[] { "Stat unit doesn't have related activity" });
            }

            if (_analysisRules.Connections.CheckAddress && unit.Address == null)
                messages.Add(nameof(StatisticalUnit.Address), new[] {"Stat unit doesn't have related address"});

            return messages;
        }
       
        public Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit)
        {
            var manager = unit is StatisticalUnit statisticalUnit
                ? new StatisticalUnitMandatoryFieldsManager(statisticalUnit, _mandatoryFields) as IAnalysisManager
                : new EnterpriseGroupMandatoryFieldsManager(unit as EnterpriseGroup, _mandatoryFields);

            return manager.CheckFields();
        }
     
        public Dictionary<string, string[]> CheckCalculationFields(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();

            if (_analysisRules.CalculationFields.StatId)
            {
                var okpo = unit is StatisticalUnit statisticalUnit ? statisticalUnit.StatId : ((EnterpriseGroup) unit).StatId;
                if (okpo == null) return messages;

                var sum = okpo.Select((s, i) => Convert.ToInt32(s) * (i + 1)).Sum();
                var remainder = sum % 11;
                if (remainder >= 10)
                    sum = okpo.Select((s, i) => Convert.ToInt32(s) * (i + 3)).Sum();

                remainder = sum % 11;
                var checkNumber = remainder >= 10 ? 0 : sum - 11 * (sum / 11);

                if (!(remainder == checkNumber || remainder == 10 && checkNumber == 0))
                    messages.Add(nameof(unit.StatId), new[] {"Stat unit's \"StatId\" is incorrect"});
            }

            return messages;
        }

        public Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<IStatisticalUnit> units)
        {
            var manager = unit is StatisticalUnit statisticalUnit
                ? new StatisticalUnitDuplicatesManager(statisticalUnit, _analysisRules, units) as IAnalysisManager
                : new EnterpriseGroupDuplicatesManager(unit as EnterpriseGroup, _analysisRules, units);

            return manager.CheckFields();
        }

        public Dictionary<string, string[]> CheckOrphanUnits(EnterpriseUnit unit)
        {
            var messages = new Dictionary<string, string[]>();

            if (_analysisRules.Orphan.CheckRelatedEnterpriseGroup && unit.EntGroupId == null)
                messages.Add(nameof(EnterpriseUnit.EntGroupId), new[] { "Enterprise has no associated with it enterprise group" });

            return messages;
        }

        public virtual AnalysisResult CheckAll(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();
            var summaryMessages = new List<string>();

            var connectionsResult = CheckConnections(unit);
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

            var calculationFieldsResult = CheckCalculationFields(unit);
            if (calculationFieldsResult.Any())
            {
                summaryMessages.Add("Calculation fields rules warnings");
                calculationFieldsResult.ForEach(d =>
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

            var potentialDuplicateUnits = GetPotentialDuplicateUnits(unit);
            if (potentialDuplicateUnits.Any())
            {
                var duplicatesResult = CheckDuplicates(unit, potentialDuplicateUnits);
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
            }

            if (unit is EnterpriseUnit)
            {
                var ophanUnitsResult = CheckOrphanUnits((EnterpriseUnit)unit);
                if (ophanUnitsResult.Any())
                {
                    summaryMessages.Add("Orphan units rules warnings");
                    messages.AddRange(ophanUnitsResult);
                }
            }

            return new AnalysisResult
            {
                Name = unit.Name,
                Type = unit.UnitType,
                Messages = messages,
                SummaryMessages = summaryMessages
            };
        }
        

        /// <summary>
        /// Метод получения потенциальных дупликатов стат. единиц
        /// </summary>
        /// <param name="unit">Стат. единица</param>
        /// <returns></returns>
        private List<IStatisticalUnit> GetPotentialDuplicateUnits(IStatisticalUnit unit)
        {
            if (unit is EnterpriseGroup enterpriseGroup)
            {
                var enterpriseGroups = _context.EnterpriseGroups
                    .Where(eg =>
                        eg.UnitType == unit.UnitType && eg.RegId != unit.RegId && eg.ParentId == null &&
                        (eg.StatId == unit.StatId && eg.TaxRegId == unit.TaxRegId || eg.ExternalId == unit.ExternalId ||
                         eg.Name == unit.Name ||
                         eg.ShortName == enterpriseGroup.ShortName ||
                         eg.TelephoneNo == enterpriseGroup.TelephoneNo ||
                         eg.AddressId == enterpriseGroup.AddressId ||
                         eg.EmailAddress == enterpriseGroup.EmailAddress ||
                         eg.ContactPerson == enterpriseGroup.ContactPerson
                        ))
                    .Select(x => (IStatisticalUnit)x).ToList();
                return enterpriseGroups;
            }

            var statUnit = (StatisticalUnit)unit;
            var statUnitPerson = statUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner);

            var units = _context.StatisticalUnits
                .Include(x => x.PersonsUnits)
                .Where(su =>
                    su.UnitType == unit.UnitType && su.RegId != unit.RegId && su.ParentId == null &&
                    ((su.StatId == unit.StatId && su.TaxRegId == unit.TaxRegId) || su.ExternalId == unit.ExternalId ||
                     su.Name == unit.Name ||
                     su.ShortName == statUnit.ShortName ||
                     su.TelephoneNo == statUnit.TelephoneNo ||
                     su.AddressId == unit.AddressId ||
                     su.EmailAddress == statUnit.EmailAddress ||
                     su.ContactPerson == statUnit.ContactPerson ||
                     su.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) != null && statUnitPerson != null &&
                     su.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner).PersonId == statUnitPerson.PersonId &&
                     su.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner).UnitId == statUnitPerson.UnitId
                     ))
                .Select(x => (IStatisticalUnit)x).ToList();

            return units;
        }
    }
}
