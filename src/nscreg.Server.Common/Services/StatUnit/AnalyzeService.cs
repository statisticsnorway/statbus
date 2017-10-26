using System;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.Contracts;
using Newtonsoft.Json;
using nscreg.Business.Analysis.StatUnit.Analyzers;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Business.Analysis.Contracts;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Класс сервис анализа
    /// </summary>
    public class AnalyzeService : IStatUnitAnalyzeService
    {
        private readonly NSCRegDbContext _context;
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly StatUnitAnalysisHelper _helper;

        public AnalyzeService(NSCRegDbContext context, StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields)
        {
            _context = context;
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
            _helper = new StatUnitAnalysisHelper(_context);
        }

        public AnalysisResult AnalyzeStatUnit(IStatisticalUnit unit)
        {
            return AnalyzeSingleStatUnit(unit, new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context));
        }

        public void AnalyzeStatUnits(AnalysisQueue analysisQueue)
        {
            analysisQueue.ServerStartPeriod = analysisQueue.ServerStartPeriod ?? DateTime.Now;
            var analyzer = new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context);

            AnalyzeStatisticalUnits(analysisQueue, analyzer);
            AnalyzeEnterpriseGroups(analysisQueue, analyzer);

            analysisQueue.ServerEndPeriod = DateTime.Now;
            _context.SaveChanges();
        }

        private static AnalysisResult AnalyzeSingleStatUnit(IStatisticalUnit unit, IStatUnitAnalyzer analyzer)
        {
            return analyzer.CheckAll(unit);
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

                var analyzeResult = AnalyzeSingleStatUnit(unitForAnalysis, analyzer);
                _context.AnalysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueue.Id,
                    AnalyzedUnitId = unitForAnalysis.RegId,
                    AnalyzedUnitType = unitForAnalysis.UnitType,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
                _context.SaveChanges();
            }
        }

        /// <summary>
        /// Анализ групп предприятий
        /// </summary>
        /// <param name="analysisQueue"></param>
        /// <param name="analyzer"></param>
        private void AnalyzeEnterpriseGroups(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer)
        {
            while (true)
            {
                var unitForAnalysis = _helper.GetEnterpriseGroupForAnalysis(analysisQueue);
                if (unitForAnalysis == null) break;

                var analyzeResult = AnalyzeSingleStatUnit(unitForAnalysis, analyzer);
                _context.AnalysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueue.Id,
                    AnalyzedUnitId = unitForAnalysis.RegId,
                    AnalyzedUnitType = unitForAnalysis.UnitType,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
                _context.SaveChanges();
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
    }
}
