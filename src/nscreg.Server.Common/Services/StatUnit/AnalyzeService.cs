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
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using NLog;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Analyze Service class
    /// </summary>
    public class AnalyzeService : IStatUnitAnalyzeService
    {
        private static Logger _logger = LogManager.GetCurrentClassLogger();
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

        public async Task<AnalysisResult> AnalyzeStatUnit(IStatisticalUnit unit, bool isAlterDataSourceAllowedOperation, bool isDataSourceUpload, bool isSkipCustomCheck)
        {
            return await AnalyzeSingleStatUnit(unit, new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context, _validationSettings, isAlterDataSourceAllowedOperation, isDataSourceUpload, isSkipCustomCheck));
        }

        public bool CheckStatUnitIdIsContains(IStatisticalUnit unit)
        {
            return _context.StatisticalUnits.Any(x => x.StatId == unit.StatId);
        }

        public async Task AnalyzeStatUnits(AnalysisQueue analysisQueue)
        {
            if (!analysisQueue.ServerStartPeriod.HasValue)
            {
                analysisQueue.ServerStartPeriod = DateTime.Now;
                await _context.SaveChangesAsync();
            }
            var analyzer = new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context, _validationSettings);
            await AnalyzeStatisticalUnits(analysisQueue, analyzer);
            await AnalyzeEnterpriseGroups(analysisQueue, analyzer);

            analysisQueue.ServerEndPeriod = DateTime.Now;
            await _context.SaveChangesAsync();
        }

        private async Task<AnalysisResult> AnalyzeSingleStatUnit(IStatisticalUnit unit, IStatUnitAnalyzer analyzer)
        {
            return await analyzer.CheckAll(unit);
        }

        /// <summary>
        /// Statistical units analysis
        /// </summary>
        /// <param name="analysisQueue">Queue item</param>
        /// <param name="analyzer">Stat unit analyzer</param>
        private async Task AnalyzeStatisticalUnits(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer)
        {
            while (true)
            {
                var unitForAnalysis = await _helper.GetStatisticalUnitForAnalysis(analysisQueue);
                if (unitForAnalysis == null) break;

                _logger.Info($"Analyze {unitForAnalysis.UnitType} unit with Id = {unitForAnalysis.RegId}, StatId = {unitForAnalysis.StatId}, Name = {unitForAnalysis.Name}");

                     await AddAnalysisLogs(analysisQueue.Id, unitForAnalysis, analyzer);
            }
        }

        /// <summary>
        /// Enterprise groups analysis
        /// </summary>
        /// <param name="analysisQueue">Queue item</param>
        /// <param name="analyzer">Stat unit analyzer</param>
        private async Task AnalyzeEnterpriseGroups(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer)
        {
            while (true)
            {
                var unitForAnalysis = await _helper.GetEnterpriseGroupForAnalysis(analysisQueue);
                if (unitForAnalysis == null) break;

                _logger.Info($"Analyze {unitForAnalysis.UnitType} with Id = {unitForAnalysis.RegId}, StatId = {unitForAnalysis.StatId}, Name = {unitForAnalysis.Name}");

                await AddAnalysisLogs(analysisQueue.Id, unitForAnalysis, analyzer);
            }
        }

        private async Task AddAnalysisLogs(int analysisQueueId, IStatisticalUnit unitForAnalysis, IStatUnitAnalyzer analyzer)
        {
            var analyzeResult = await AnalyzeSingleStatUnit(unitForAnalysis, analyzer);
            _context.AnalysisLogs.Add(new AnalysisLog
            {
                AnalysisQueueId = analysisQueueId,
                AnalyzedUnitId = unitForAnalysis.RegId,
                AnalyzedUnitType = unitForAnalysis.UnitType,
                IssuedAt = DateTime.Now,
                SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
            });
            await _context.SaveChangesAsync();
        }
    }
}
