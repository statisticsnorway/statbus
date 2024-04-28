//using Microsoft.AspNetCore.Mvc.Formatters.Internal;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.Analysis.Contracts;
using nscreg.Business.Analysis.StatUnit.Managers.AnalysisChecks;
using nscreg.Business.Analysis.StatUnit.Managers.Duplicates;
using nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields;
using nscreg.Business.PredicateBuilders;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Business.Analysis.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Statistical unit analyzer
    /// </summary>
    public class StatUnitAnalyzer : IStatUnitAnalyzer
    {
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly NSCRegDbContext _context;
        private readonly ValidationSettings _validationSettings;
        private readonly bool _isAlterDataSourceAllowedOperation;
        private readonly bool _isDataSourceUpload;
        private readonly bool _isSkipCustomCheck;
        private readonly IEnumerable<PropertyInfo> _orphanProperties;

        public StatUnitAnalyzer(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields,
            NSCRegDbContext context, ValidationSettings validationSettings, bool isAlterDataSourceAllowedOperation = false, bool isDataSourceUpload = false, bool isSkipCustomCheck = false)
        {
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
            _context = context;
            _isDataSourceUpload = isDataSourceUpload;
            _validationSettings = validationSettings;
            _isSkipCustomCheck = isSkipCustomCheck;
            _isAlterDataSourceAllowedOperation = isAlterDataSourceAllowedOperation;
            _orphanProperties = _analysisRules.Orphan.GetType().GetProperties()
                .Where(x => (bool)x.GetValue(_analysisRules.Orphan, null) == true);
        }

        /// <inheritdoc />
        /// <summary>
        /// Check statistical unit connections
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Dictionary of messages</returns>
        public async Task<Dictionary<string, string[]>> CheckConnections(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();

            if (_analysisRules.Connections.CheckRelatedPersons && !(unit is EnterpriseGroup))
            {
                if (unit.PersonsUnits != null && !unit.PersonsUnits.Any())
                {
                    if (!await _context.PersonStatisticalUnits.AnyAsync(c => c.UnitId == unit.RegId))
                    {
                        messages.Add(unit is LocalUnit ? nameof(LocalUnit.LegalUnitId) : nameof(EnterpriseUnit.LegalUnits),
                            new[] { nameof(Resource.AnalysisRelatedPersons) });
                    }

                }
            }

            if (_analysisRules.Connections.CheckRelatedActivities && !(unit is EnterpriseGroup))
            {
                if (unit.ActivitiesUnits != null &&  !unit.ActivitiesUnits.Any())
                {
                    if(!await _context.ActivityStatisticalUnits.AnyAsync(c => c.UnitId == unit.RegId))
                    {
                        messages.Add(nameof(StatisticalUnit.Activities), new[] { nameof(Resource.AnalysisRelatedActivity) });
                    }
                }
            }

            if (_analysisRules.Connections.CheckAddress && _isDataSourceUpload == false && unit.ActualAddress == null)
                messages.Add(nameof(StatisticalUnit.ActualAddress), new[] { nameof(Resource.AnalysisRelatedAddress) });

            return messages;
        }

        /// <inheritdoc />
        /// <summary>
        /// Check statistical unit mandatory fields
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit)
        {
            IMandatoryFieldsAnalysisManager manager = unit is StatisticalUnit statisticalUnit
                ? new StatisticalUnitMandatoryFieldsManager(statisticalUnit, _mandatoryFields, _context) as IMandatoryFieldsAnalysisManager
                : new EnterpriseGroupMandatoryFieldsManager(unit as EnterpriseGroup, _mandatoryFields);

            return _isAlterDataSourceAllowedOperation
                ? manager.CheckOnlyIdentifiersFields()
                : manager.CheckFields();
        }

        /// <inheritdoc />
        /// <summary>
        /// Check statistical unit calculation fields
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckCalculationFields(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();

            var okpo = unit.StatId;

            if (string.IsNullOrEmpty(okpo) || !_validationSettings.ValidateStatIdChecksum) return messages;

            if (okpo.Any(x => !char.IsDigit(x)))
            {
                messages.Add(nameof(unit.StatId), new[] { nameof(Resource.AnalysisCalculationsStatIdOnlyNumber) });
                return messages;
            }

            if (okpo.Length < 8)
            {
                okpo = okpo.PadLeft(8, '0');
            }

            var okpoWithoutCheck = okpo.Substring(0, okpo.Length - 1);
            var checkNumber = Convert.ToInt32(okpo.Last().ToString());

            var sum = okpoWithoutCheck.Select((s, i) => Convert.ToInt32(s.ToString()) * (i % 10 + 1)).Sum();
            var remainder = sum % 11;
            if (remainder >= 10)
            {
                sum = okpoWithoutCheck.Select((s, i) => Convert.ToInt32(s.ToString()) * (i % 10 + 3)).Sum();
                remainder = sum % 11;
            }

            if (!(remainder == checkNumber || remainder == 10))
                messages.Add(nameof(unit.StatId), new[] { nameof(Resource.AnalysisCalculationsStatId) });

            return messages;
        }

        /// <inheritdoc />
        /// <summary>
        /// Check statistical unit duplicates
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <param name="units">Duplicate units</param>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<AnalysisDublicateResult> units)
        {
            var manager = unit is StatisticalUnit statisticalUnit
                ? new StatisticalUnitDuplicatesManager(statisticalUnit, _analysisRules, units) as IAnalysisManager
                : new EnterpriseGroupDuplicatesManager(unit as EnterpriseGroup, _analysisRules, units);

            return manager.CheckFields();
        }

        /// <summary>
        /// Check statistical unit for orphanness
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Dictionary of messages</returns>
        public async Task<Dictionary<string, string[]>> CheckOrphanUnits(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();
            foreach (var orphanProperty in _orphanProperties)
            {
                if (unit is EnterpriseUnit enterpriseUnit)
                {
                    await CheckUnit(enterpriseUnit, orphanProperty.Name, messages);
                }
                else if (unit is LegalUnit legalUnit)
                {
                   await CheckUnit(legalUnit, orphanProperty.Name, messages);
                }
                else if (unit is LocalUnit localUnit)
                {
                   await CheckUnit(localUnit, orphanProperty.Name, messages);
                }
                else if (unit is EnterpriseGroup group)
                {
                  await  CheckUnit(group, orphanProperty.Name, messages);
                }
            }
            return messages;
        }

        private async Task CheckUnit(EnterpriseUnit unit, string propertyName, Dictionary<string, string[]> messages)
        {
            switch (propertyName)
            {
                case nameof(Orphan.CheckEnterpriseRelatedLegalUnits):
                    if (CheckUnitStatus(unit))
                    {
                        if (!unit.LegalUnits.Any())
                        {
                            if(!await _context.LegalUnits.AnyAsync(c => c.EnterpriseUnitRegId == unit.RegId))
                            {
                                messages.Add(nameof(EnterpriseUnit.LegalUnits), new[] { nameof(Resource.AnalysisEnterpriseRelatedLegalUnits) });
                            }
                        }
                    }
                    break;
            }
        }
        private async Task CheckUnit(EnterpriseGroup unit, string propertyName, Dictionary<string, string[]> messages)
        {
            if (propertyName != nameof(Orphan.CheckEnterpriseGroupRelatedEnterprises)) return;
            if (CheckUnitStatus(unit))
            {
                if (!unit.EnterpriseUnits.Any())
                {
                    if(!await _context.EnterpriseUnits.AnyAsync(c => c.EntGroupId == unit.RegId))
                    {
                        messages.Add(nameof(EnterpriseGroup.EnterpriseUnits), new[] { nameof(Resource.AnalysisEnterpriseRelatedLegalUnits) });
                    }
                }

            }
        }

        private async Task CheckUnit(LegalUnit unit, string propertyName, Dictionary<string, string[]> messages)
        {
            switch (propertyName)
            {
                case nameof(Orphan.CheckOrphanLegalUnits):
                {
                    if (CheckUnitStatus(unit))
                    {
                        if (unit.EnterpriseUnitRegId == null)
                        {
                            messages.Add(nameof(LegalUnit.EnterpriseUnitRegId),
                                new[] { nameof(Resource.AnalysisOrphanLegalUnits) });
                        }
                        else
                        {
                            if (await CheckUnitParentStatus(unit) == false)
                            {
                                messages.Add(nameof(LegalUnit.EnterpriseUnitRegId),
                                    new[] { nameof(Resource.AnalysisOrphanLegalUnitHaveParentWithInactiveStatus) });
                            }
                        }

                    }
                    break;
                }
                case nameof(Orphan.CheckLegalUnitRelatedLocalUnits):
                {
                    if (CheckUnitStatus(unit))
                    {
                        if (!unit.LocalUnits.Any())
                        {
                            if (!await _context.LocalUnits.AnyAsync(c => c.LegalUnitId == unit.RegId))
                            {
                                messages.Add(nameof(LegalUnit.LocalUnits), new[] { nameof(Resource.AnalysisRelatedLocalUnits) });
                            }
                        }
                    }
                    break;
                }
            }
        }

        private async Task CheckUnit(LocalUnit unit, string propertyName, Dictionary<string, string[]> messages)
        {
            if (propertyName != nameof(Orphan.CheckOrphanLocalUnits)) return;
            if (!CheckUnitStatus(unit)) return;
            if (unit.LegalUnitId == null)
            {
                messages.Add(nameof(LocalUnit.LegalUnitId), new[] { nameof(Resource.AnalysisOrphanLocalUnits) });
            }
            else
            {
                if(await CheckUnitParentStatus(unit) == false)
                {

                    messages.Add(nameof(LocalUnit.LegalUnitId), new[] { nameof(Resource.AnalysisOrphanLocalUnitsHaveParentWithInactiveStatus) });
                }
            }
        }

        /// <inheritdoc />
        /// <summary>
        /// Analyze statistical unit
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Dictionary of messages</returns>
        public async Task<AnalysisResult> CheckAll(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();
            var summaryMessages = new List<string>();

            var connectionsResult = await CheckConnections(unit);
            if (connectionsResult.Any())
            {
                summaryMessages.Add(nameof(Resource.ConnectionRulesWarnings));
                messages.AddRange(connectionsResult);
            }

            var mandatoryFieldsResult = CheckMandatoryFields(unit);
            if (mandatoryFieldsResult.Any())
            {
                summaryMessages.Add(nameof(Resource.MandatoryFieldsRulesWarnings));
                mandatoryFieldsResult.ForEach(d =>
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

            var calculationFieldsResult = CheckCalculationFields(unit);
            if (calculationFieldsResult.Any())
            {
                summaryMessages.Add(nameof(Resource.CalculationFieldsRulesWarnings));
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

            var potentialDuplicateUnits = await GetDuplicateUnits(unit);

            if (potentialDuplicateUnits.Any())
            {
                var duplicatesResult = CheckDuplicates(unit, potentialDuplicateUnits);
                if (duplicatesResult.Any())
                {
                    summaryMessages.Add(nameof(Resource.DuplicateFieldsRulesWarnings));

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

            if (!_isSkipCustomCheck)
            {
                var additionalAnalysisCheckResult = CheckCustomAnalysisChecks(unit);
                if (additionalAnalysisCheckResult.Any())
                {
                    additionalAnalysisCheckResult.Values.ForEach(d =>
                    {
                        d.ForEach(value =>
                        {
                            if (value == unit.RegId.ToString() && !summaryMessages.Contains(nameof(Resource.CustomAnalysisChecks)))
                            {
                                summaryMessages.Add(nameof(Resource.CustomAnalysisChecks));
                            }
                        });
                    });
                    additionalAnalysisCheckResult.ForEach(d =>
                    {
                        if (messages.ContainsKey(d.Key))
                        {
                            var existed = messages[d.Key];
                            messages[d.Key] = existed.Concat(d.Value).ToArray();
                        }
                        if (d.Value.FirstOrDefault(c => c == unit.RegId.ToString()) != null)
                        {
                            messages.Add(d.Key, new[] { "warning" });
                        }
                    });
                }
               // AnalyzeTracer.CheckCustomAnalysisChecks.Stop();
               // AnalyzeTracer.countCheckCustomAnalysisChecks++;
            }
            // AnalyzeTracer.CheckOrphanUnits.Start();
            var ophanUnitsResult = await CheckOrphanUnits(unit);
            if (ophanUnitsResult.Any())
            {
                summaryMessages.Add(nameof(Resource.OrphanUnitsRulesWarnings));
                messages.AddRange(ophanUnitsResult);
            }
            // AnalyzeTracer.CheckOrphanUnits.Stop();
            // AnalyzeTracer.countCheckOrphanUnits++;

            // AnalyzeTracer.CheckAll.Stop();
            // AnalyzeTracer.countCheckAll++;

            return new AnalysisResult
            {
                Name = unit.Name,
                Type = unit.UnitType,
                Messages = messages,
                SummaryMessages = summaryMessages
            };
        }

        /// <summary>
        /// Checks all custom analysis rules
        /// </summary>
        /// <param name="unit">unit to analyze</param>
        /// <returns></returns>
        public Dictionary<string, string[]> CheckCustomAnalysisChecks(IStatisticalUnit unit)
        {
            return _analysisRules.CustomAnalysisChecks
                ? new StatUnitCustomCheckManager(unit, _context).CheckFields()
                : new Dictionary<string, string[]>();
        }


        /// <summary>
        /// Get statistical unit duplicates
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>List of duplicates</returns>
        private async Task<List<AnalysisDublicateResult>> GetDuplicateUnits(IStatisticalUnit unit)
        {
            if (unit is EnterpriseGroup enterpriseGroup)
            {
                var egPredicateBuilder = new AnalysisPredicateBuilder<EnterpriseGroup>();
                var egPredicate = egPredicateBuilder.GetPredicate(enterpriseGroup);
                var enterpriseGroups = await _context.EnterpriseGroups
                    .Where(egPredicate)
                    .Select(x => new AnalysisDublicateResult
                {
                    Name = x.Name,
                    StatId = x.StatId,
                    TaxRegId = x.TaxRegId,
                    ExternalId = x.ExternalId,
                    ShortName = x.ShortName,
                    TelephoneNo = x.TelephoneNo,
                    ActualAddressId = x.ActualAddressId,
                    EmailAddress = x.EmailAddress
                }).ToListAsync();
                return enterpriseGroups;
            }
            var suPredicateBuilder = new AnalysisPredicateBuilder<StatisticalUnit>();
            var suPredicate = suPredicateBuilder.GetPredicate((StatisticalUnit)unit);
            var units = await _context.StatisticalUnits
                .Include(x => x.PersonsUnits)
                .Where(suPredicate)
                .Select(x => new AnalysisDublicateResult
                {
                    Name = x.Name,
                    StatId = x.StatId,
                    TaxRegId = x.TaxRegId,
                    ExternalId = x.ExternalId,
                    ShortName = x.ShortName,
                    TelephoneNo = x.TelephoneNo,
                    EmailAddress = x.EmailAddress
                })
                .ToListAsync();
            return units;
        }

        private bool CheckUnitStatus(IStatisticalUnit unit)
        {
            return unit.UnitStatusId == 1 || unit.UnitStatusId == 2 || unit.UnitStatusId == 6 ||
                   unit.UnitStatusId == 9;
        }
        private async Task<bool> CheckUnitParentStatus(IStatisticalUnit unit)
        {
            if (unit is LocalUnit lUnit)
            {
                var parentUnit = await _context.StatisticalUnits.FirstOrDefaultAsync(c => c.RegId == lUnit.LegalUnitId);
                return parentUnit != null && (parentUnit.UnitStatusId == 1 || parentUnit.UnitStatusId == 2 ||
                                              parentUnit.UnitStatusId == 9);

            }
            if (unit is LegalUnit legUnit)
            {
                var parentUnit = await _context.StatisticalUnits.FirstOrDefaultAsync(c => c.RegId == legUnit.EnterpriseUnitRegId);
                return parentUnit != null && (parentUnit.UnitStatusId == 1 || parentUnit.UnitStatusId == 2 ||
                                              parentUnit.UnitStatusId == 9);
            }
            if (unit is EnterpriseUnit enUnit)
            {
                var parentUnit = await _context.StatisticalUnits.FirstOrDefaultAsync(c => c.RegId == enUnit.EntGroupId);
                return parentUnit != null && (parentUnit.UnitStatusId == 1 || parentUnit.UnitStatusId == 2 ||
                                              parentUnit.UnitStatusId == 9);
            }
            return false;
        }
    }
}
