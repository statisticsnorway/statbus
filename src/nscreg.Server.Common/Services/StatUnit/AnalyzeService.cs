using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data.Constants;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.Contracts;
using Newtonsoft.Json;
using nscreg.Business.Analysis.StatUnit.Analyzers;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Класс сервис анализа
    /// </summary>
    public class AnalyzeService : IStatUnitAnalyzeService
    {
        private readonly NSCRegDbContext _ctx;
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly StatUnitAnalysisHelper _helper;

        public AnalyzeService(NSCRegDbContext ctx, StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields)
        {
            _ctx = ctx;
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
            _helper = new StatUnitAnalysisHelper(_ctx);
        }

        /// <inheritdoc />
        /// <summary>
        /// Analyzes stat unit
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        public AnalysisResult AnalyzeStatUnit(IStatisticalUnit unit, IStatUnitAnalyzer analyzer)
        {
            var addresses = _ctx.Address.Where(adr => adr.Id == unit.AddressId).ToList();
            var potentialDuplicateUnits = GetPotentialDuplicateUnits(unit);

            return analyzer.CheckAll(unit, HasRelatedLegalUnit(unit), HasRelatedAcitivities(unit), addresses, potentialDuplicateUnits);
        }

        /// <inheritdoc />
        /// <summary>
        /// Analyzes stat units
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        public void AnalyzeStatUnits(AnalysisQueue analysisQueue)
        {
            analysisQueue.ServerStartPeriod = analysisQueue.ServerStartPeriod ?? DateTime.Now;

            AnalyzeStatisticalUnits(analysisQueue, new StatisticalUnitAnalyzer(_analysisRules, _mandatoryFields));
            AnalyzeEnterpriseGroups(analysisQueue, new EnterpriseGroupAnalyzer(_analysisRules, _mandatoryFields));
        }

        /// <summary>
        /// Анализ статистических единиц
        /// </summary>
        /// <param name="analysisQueue"></param>
        /// <param name="analyzer"></param>
        private void AnalyzeStatisticalUnits(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer)
        {
            while (true)
            {
                var unitForAnalysis = _helper.GetStatisticalUnitForAnalysis(analysisQueue);
                if (unitForAnalysis == null) break;

                var analyzeResult = AnalyzeStatUnit(unitForAnalysis, analyzer);
                _ctx.AnalysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueue.Id,
                    AnalyzedUnitId = unitForAnalysis.RegId,
                    AnalyzedUnitType = unitForAnalysis.UnitType,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
                _ctx.SaveChanges();
            }
        }

        /// <summary>
        /// Анализ групп предприятий
        /// </summary>
        /// <param name="analysisQueue"></param>
        /// <param name="enterpriseGroupAnalyzer"></param>
        private void AnalyzeEnterpriseGroups(AnalysisQueue analysisQueue, IStatUnitAnalyzer enterpriseGroupAnalyzer)
        {
            while (true)
            {
                var unitForAnalysis = _helper.GetEnterpriseGroupForAnalysis(analysisQueue);
                if (unitForAnalysis == null) break;

                var analyzeResult = AnalyzeStatUnit(unitForAnalysis, enterpriseGroupAnalyzer);
                _ctx.AnalysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueue.Id,
                    AnalyzedUnitId = unitForAnalysis.RegId,
                    AnalyzedUnitType = unitForAnalysis.UnitType,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
                _ctx.SaveChanges();
            }
        }



        /// <summary>
        /// Метод получения несовместимых записей
        /// </summary>
        /// <param name="model">Модель запроса пагинации</param>
        /// <param name="analysisLogId">Идентификатор журнала анализа</param>
        /// <returns></returns>
        public SearchVm<InconsistentRecord> GetInconsistentRecords(PaginatedQueryM model, int analysisLogId)
        {
            return null;
            //var summaryMessages = _ctx.AnalysisLogs.FirstOrDefault(al => al.Id == analysisLogId).SummaryMessages;

            //// TODO: get rid of `GroupBy` on `EF.DbSet`
            //var analyzeGroupErrors = _ctx.AnalysisGroupErrors.Where(ae => ae.AnalysisLogId == analysisLogId)
            //    .Include(x => x.EnterpriseGroup).ToList().GroupBy(x => x.GroupRegId)
            //    .Select(g => g.First()).ToList();

            //var analyzeStatisticalErrors = _ctx.AnalysisStatisticalErrors.Where(ae => ae.AnalysisLogId == analysisLogId)
            //    .Include(x => x.StatisticalUnit).ToList().GroupBy(x => x.StatisticalRegId)
            //    .Select(g => g.First());

            //var records = new List<InconsistentRecord>();

            //records.AddRange(analyzeGroupErrors.Select(error => new InconsistentRecord(error.GroupRegId,
            //    error.EnterpriseGroup.UnitType, error.EnterpriseGroup.Name, summaryMessages)));
            //records.AddRange(analyzeStatisticalErrors.Select(error => new InconsistentRecord(error.StatisticalRegId,
            //    error.StatisticalUnit.UnitType, error.StatisticalUnit.Name, summaryMessages)));

            //var total = records.Count;
            //var skip = model.PageSize * (model.Page - 1);
            //var take = model.PageSize;

            //var paginatedRecords = records.OrderBy(v => v.Type).ThenBy(v => v.Name)
            //    .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
            //    .Take(take)
            //    .ToList();

            //return SearchVm<InconsistentRecord>.Create(paginatedRecords, total);

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
                var enterpriseGroups = _ctx.EnterpriseGroups
                    .Where(eg =>
                        eg.UnitType == unit.UnitType && eg.RegId != unit.RegId && eg.ParentId == null &&
                        ((eg.StatId == unit.StatId && eg.TaxRegId == unit.TaxRegId) || eg.ExternalId == unit.ExternalId ||
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

            var units = _ctx.StatisticalUnits
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

        /// <summary>
        /// Метод определения соответствия правовой единицы
        /// </summary>
        /// <param name="unit">Стат. единица</param>
        /// <returns></returns>
        private static bool HasRelatedLegalUnit(IStatisticalUnit unit)
        {
            switch (unit.UnitType)
            {
                case StatUnitTypes.LocalUnit:
                    return ((LocalUnit)unit).LegalUnitId != null;
                case StatUnitTypes.EnterpriseUnit:
                    return ((EnterpriseUnit) unit).LegalUnits.Any();
                case StatUnitTypes.LegalUnit:
                    return true;
                case StatUnitTypes.EnterpriseGroup:
                    return true;
                default:
                    return false;
            }
        }

        /// <summary>
        /// Метод определения соответствия деятельностей
        /// </summary>
        /// <param name="unit">Стат. единица</param>
        /// <returns></returns>
        private static bool HasRelatedAcitivities(IStatisticalUnit unit)
        {
            if (unit is EnterpriseGroup || unit is LegalUnit) return true;

            var statUnit = (StatisticalUnit)unit;
            return statUnit.ActivitiesUnits.Any();
        }

    }
}
