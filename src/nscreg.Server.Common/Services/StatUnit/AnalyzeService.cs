using System;
using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.Contracts;
using Newtonsoft.Json;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Business.Analysis.Contracts;
using nscreg.Data.Constants;
using nscreg.Utilities.Configuration;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Analyze Service class
    /// </summary>
    public class AnalyzeService : IStatUnitAnalyzeService
    {
        private readonly NSCRegDbContext _context;
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly StatUnitAnalysisHelper _helper;
        private readonly ValidationSettings _validationSettings;

        public AnalyzeService(NSCRegDbContext context, StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields, ValidationSettings validationSettings)
        {
            _context = context;
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
            _helper = new StatUnitAnalysisHelper(_context);
            _validationSettings = validationSettings;
        }

        public AnalysisResult AnalyzeStatUnit(IStatisticalUnit unit, bool isAlterDataSourceAllowedOperation)
        {
            return AnalyzeSingleStatUnit(unit, new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context, _validationSettings));
        }

        public bool CheckStatUnitIdIsContains(IStatisticalUnit unit)
        {
            return _context.StatisticalUnits.Any(x => x.StatId == unit.StatId);
        }

        public void AnalyzeStatUnits(AnalysisQueue analysisQueue)
        {
            if (!analysisQueue.ServerStartPeriod.HasValue)
            {
                analysisQueue.ServerStartPeriod = DateTime.Now;
                _context.SaveChanges();
            }
            var analyzer = new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context, _validationSettings);

            AnalyzeStatisticalUnits(analysisQueue, analyzer);
            AnalyzeEnterpriseGroups(analysisQueue, analyzer);

            analysisQueue.ServerEndPeriod = DateTime.Now;
            _context.SaveChanges();
        }

        private static AnalysisResult AnalyzeSingleStatUnit(IStatisticalUnit unit, IStatUnitAnalyzer analyzer, bool isAlterDataSourceAllowedOperation = false)
        {
            if (isAlterDataSourceAllowedOperation)
            {
                //return analyzer.
            }
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
                AddAnalysisLogs(analysisQueue.Id, unitForAnalysis, analyzer);
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
                AddAnalysisLogs(analysisQueue.Id, unitForAnalysis, analyzer);
            }
        }

        private void AddAnalysisLogs(int analysisQueueId, IStatisticalUnit unitForAnalysis, IStatUnitAnalyzer analyzer)
        {
            var analyzeResult = AnalyzeSingleStatUnit(unitForAnalysis, analyzer);
            if (analyzeResult.Messages.Any() || analyzeResult.SummaryMessages.Any())
            {
                _context.AnalysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueueId,
                    AnalyzedUnitId = unitForAnalysis.RegId,
                    AnalyzedUnitType = unitForAnalysis.UnitType,
                    IssuedAt = DateTime.Now,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
                _context.SaveChanges();
            }
        }
    }
}
