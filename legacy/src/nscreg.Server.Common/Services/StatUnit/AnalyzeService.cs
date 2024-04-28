using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Newtonsoft.Json;
using NLog;
using nscreg.Business.Analysis.Contracts;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <inheritdoc />
    /// <summary>
    /// Analyze Service class
    /// </summary>
    public class AnalyzeService : IStatUnitAnalyzeService
    {
        //private static Logger _logger = LogManager.GetCurrentClassLogger();
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
                analysisQueue.ServerStartPeriod = DateTimeOffset.Now;
                await _context.SaveChangesAsync();
            }
            var analyzer = new StatUnitAnalyzer(_analysisRules, _mandatoryFields, _context, _validationSettings);
            await BulkAnalyzeStatisticalUnits(analysisQueue, analyzer);
            await BulkAnalyzeEnterpriseGroups(analysisQueue, analyzer);

            analysisQueue.ServerEndPeriod = DateTimeOffset.Now;
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
                     await AddAnalysisLogs(analysisQueue.Id, unitForAnalysis, analyzer);
            }
        }
        /// <summary>
        /// Statistical units analysis
        /// </summary>
        /// <param name="analysisQueue">Queue item</param>
        /// <param name="analyzer">Stat unit analyzer</param>
        private async Task BulkAnalyzeStatisticalUnits(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer)
        {
            var skipCount = 0;
            var takeCount = 1000;
            var unitsForAnalysis = await _helper.GetStatisticalUnitsForAnalysis(analysisQueue, skipCount, takeCount);
            while (unitsForAnalysis.Any())
            {
                await AnalyzeStatUnitsAndCreateLogs(analysisQueue, analyzer, unitsForAnalysis);
                skipCount += unitsForAnalysis.Count;
                unitsForAnalysis.Clear();
                unitsForAnalysis = await _helper.GetStatisticalUnitsForAnalysis(analysisQueue, skipCount, takeCount);
            }
        }

        private async Task AnalyzeStatUnitsAndCreateLogs(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer,
            List<StatisticalUnit> unitsForAnalysis)
        {
            var analysisLogs = new List<AnalysisLog>();

            foreach (var x in unitsForAnalysis)
            {
                var analyzeResult = await AnalyzeSingleStatUnit(x, analyzer);
                //_logger.Info($"Analyze {x.UnitType} unit with Id = {x.RegId}, StatId = {x.StatId}, Name = {x.Name}");

                analysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueue.Id,
                    AnalyzedUnitId = x.RegId,
                    AnalyzedUnitType = x.UnitType,
                    IssuedAt = DateTime.Now,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
            }

            await _context.AnalysisLogs.AddRangeAsync(analysisLogs);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Enterprise groups bulk analysis
        /// </summary>
        private async Task BulkAnalyzeEnterpriseGroups(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer)
        {
            var skipCount = 0;
            var takeCount = 1000;
            var unitsForAnalysis = await _helper.GetEnterpriseGroupsForAnalysis(analysisQueue, skipCount, takeCount);
            while (unitsForAnalysis.Any())
            {
                await AnalyzeEnterpriseGroupsAndCreateLogs(analysisQueue, analyzer, unitsForAnalysis);
                skipCount += unitsForAnalysis.Count;
                unitsForAnalysis.Clear();
                unitsForAnalysis = await _helper.GetEnterpriseGroupsForAnalysis(analysisQueue, skipCount, takeCount);
            }
        }

        private async Task AnalyzeEnterpriseGroupsAndCreateLogs(AnalysisQueue analysisQueue, IStatUnitAnalyzer analyzer,
            List<EnterpriseGroup> unitsForAnalysis)
        {
            var analysisLogs = new List<AnalysisLog>();
            foreach (var x in unitsForAnalysis)
            {
                var analyzeResult = await AnalyzeSingleStatUnit(x, analyzer);
                //_logger.Info($"Analyze {x.UnitType} unit with Id = {x.RegId}, StatId = {x.StatId}, Name = {x.Name}");

                analysisLogs.Add(new AnalysisLog
                {
                    AnalysisQueueId = analysisQueue.Id,
                    AnalyzedUnitId = x.RegId,
                    AnalyzedUnitType = x.UnitType,
                    IssuedAt = DateTime.Now,
                    SummaryMessages = string.Join(";", analyzeResult.SummaryMessages),
                    ErrorValues = JsonConvert.SerializeObject(analyzeResult.Messages)
                });
            }

            await _context.AnalysisLogs.AddRangeAsync(analysisLogs);
            await _context.SaveChangesAsync();
        }

        private async Task AddAnalysisLogs(int analysisQueueId, IStatisticalUnit unitForAnalysis, IStatUnitAnalyzer analyzer)
        {
            var analyzeResult = await AnalyzeSingleStatUnit(unitForAnalysis, analyzer);
            //_logger.Info($"Analyze {unitForAnalysis.UnitType} unit with Id = {unitForAnalysis.RegId}, StatId = {unitForAnalysis.StatId}, Name = {unitForAnalysis.Name}");

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
