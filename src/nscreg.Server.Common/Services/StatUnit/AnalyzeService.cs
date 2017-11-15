using System;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.Contracts;
using Newtonsoft.Json;
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
        /// Statistical units analysis
        /// </summary>
        /// <param name="analysisQueue">Queue item</param>
        /// <param name="analyzer">Stat unit analyzer</param>
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
        /// Enterprise groups analysis
        /// </summary>
        /// <param name="analysisQueue">Queue item</param>
        /// <param name="analyzer">Stat unit analyzer</param>
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
    }
}
