using Microsoft.EntityFrameworkCore.Internal;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using LogStatus = nscreg.Data.Constants.DataUploadingLogStatuses;
using QueueStatus = nscreg.Data.Constants.DataSourceQueueStatuses;

namespace nscreg.Server.DataUploadSvc
{
    /// <summary>
    /// Queue class
    /// </summary>
    internal class QueueJob : IJob
    {
        private readonly ILogger _logger;
        public int Interval { get; }
        private QueueService _queueSvc;
        private DbLogBuffer _logBuffer;
        private AnalyzeService _analysisSvc;
        private readonly int _dbLogBufferMaxCount;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly ValidationSettings _validationSettings;
        private NSCRegDbContext _context;
        public QueueJob(
            int dequeueInterval,
            ILogger logger,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields,
            ValidationSettings validationSettings, int bufferLogMaxCount)
        {
            _logger = logger;
            Interval = dequeueInterval;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _dbMandatoryFields = dbMandatoryFields;
            _validationSettings = validationSettings;
            _dbLogBufferMaxCount = bufferLogMaxCount;
            AddScopedServices();
        }

        private void AddScopedServices()
        {
            var dbContextHelper = new DbContextHelper();
            _context = dbContextHelper.CreateDbContext(new string[] { });
            _queueSvc = new QueueService(_context);
            _analysisSvc = new AnalyzeService(_context, _statUnitAnalysisRules, _dbMandatoryFields, _validationSettings);
            var editSvc = new EditService(_context, _statUnitAnalysisRules, _dbMandatoryFields, _validationSettings, shouldAnalyze: false);
            _logBuffer = new DbLogBuffer(_context, _dbLogBufferMaxCount);
        }

        /// <summary>
        /// Queue execution method
        /// </summary>
        public async Task Execute(CancellationToken cancellationToken)
        {
            AddScopedServices();
            _logger.LogInformation("dequeue attempt...");
            var (dequeueError, dequeued) = await Dequeue();
            if (dequeueError.HasValue())
            {
                _logger.LogInformation("dequeue failed with error: {0}", dequeueError);
                return;
            }
            if (dequeued == null) return;

            _logger.LogInformation("mutation queue file #{0}", dequeued.Id);

            var mutateError = await MutateFileAsync(dequeued);
            if (mutateError.HasValue())
            {
                _logger.LogInformation("finish queue item with error: {0}", mutateError);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, mutateError);
            }

            Stopwatch swCycle = new Stopwatch();
            swCycle.Start();

            _logger.LogInformation("parsing queue entry #{0}", dequeued.Id);
            Stopwatch swParseFile = new Stopwatch();
            swParseFile.Start();

            var (parseError, parsed) = await ParseFile(dequeued);

            swParseFile.Stop();
            if (parseError.HasValue())
            {
                _logger.LogInformation("finish queue item with error: {0}", parseError);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, parseError);
                return;
            }

            _logger.LogInformation("parsed {0} entities", parsed.Length);

            var anyWarnings = false;

            var populateService = new PopulateService(dequeued.DataSource.VariablesMappingArray, dequeued.DataSource.AllowedOperations, dequeued.DataSource.DataSourceUploadType, dequeued.DataSource.StatUnitType, _context);
            await populateService.InitializeCacheForLookups();

            var saveService = new SaveManager(_context, _queueSvc);
            

            Stopwatch swPopulation = new Stopwatch();
            long populationCount = 0;

            Stopwatch swAnalyze = new Stopwatch();
            long analyzeCount = 0;

            Stopwatch swSave = new Stopwatch();
            long saveCount = 0;

            Stopwatch swDbLog = new Stopwatch();
            long dbLogCount = 0;
            for (var i = 0; i < parsed.Length; i++)
            {

                _logger.LogInformation("processing entity #{0} ({1:0.00} %)", i + 1, (double)i/parsed.Length * 100);
                var startedAt = DateTime.Now;

                /// Populate Unit
                
                swPopulation.Start();
                _logger.LogInformation("populating unit");

                var (populated, isNew, populateError) = await populateService.PopulateAsync(parsed[i]);
                swPopulation.Stop();
                populationCount += 1;

                if (populateError.HasValue())
                {
                    _logger.LogInformation("error during populating of unit: {0}", populateError);
                    anyWarnings = true;
                    await LogUpload(LogStatus.Error, populateError, analysisSummary: new List<string>() { populateError });
                    continue;
                }

                populated.DataSource = dequeued.DataSourceFileName;
                populated.ChangeReason = ChangeReasons.Edit;
                populated.EditComment = "Uploaded from data source file";

                /// Analyze Unit

                _logger.LogInformation(
                    "analyzing populated unit #{0} RegId={1}", i + 1,
                    populated.RegId > 0 ? populated.RegId.ToString() : "(new)");

                swAnalyze.Start();

                var (analysisError, (errors, summary)) = AnalyzeUnit(populated, dequeued);

                swAnalyze.Stop();
                analyzeCount += 1;

                if (analysisError.HasValue())
                {
                    _logger.LogInformation("analysis attempt failed with error: {0}", analysisError);
                    anyWarnings = true;
                    await LogUpload(LogStatus.Error, analysisError);
                    continue;
                }
                if (errors.Any())
                {
                    _logger.LogInformation("analysis revealed {0} errors", errors.Count);
                    errors.Values.ForEach(x => x.ForEach(e => _logger.LogInformation(Resource.ResourceManager.GetString(e.ToString()))));
                    anyWarnings = true;
                    await LogUpload(LogStatus.Warning, string.Join(",", errors.SelectMany(c => c.Value)), errors, summary);
                    continue;
                }

                /// Save Unit

                _logger.LogInformation("saving unit");

                swSave.Start();
                var (saveError, saved) = await saveService.SaveUnit(populated, dequeued.DataSource, dequeued.UserId, isNew);

                swSave.Stop();
                saveCount += 1;

                if (saveError.HasValue())
                {
                    _logger.LogError(saveError);
                    anyWarnings = true;
                    await LogUpload(LogStatus.Warning, saveError);
                    continue;
                }

                if (!saved) anyWarnings = true;
                await LogUpload(saved ? LogStatus.Done : LogStatus.Warning);

                async Task LogUpload(LogStatus status, string note = "",
                    IReadOnlyDictionary<string, string[]> analysisErrors = null,
                    IEnumerable<string> analysisSummary = null)
                {
                    swDbLog.Start();
                    var rawUnit = JsonConvert.SerializeObject(dequeued.DataSource.VariablesMappingArray.ToDictionary(x => x.target, x =>
                             {
                                 var tmp = x.source.Split('.');
                                 if (parsed[i].ContainsKey(tmp[0]))
                                     return JsonConvert.SerializeObject(parsed[i][tmp[0]]);
                                 return tmp[0];
                             }));
                    await _logBuffer.LogUnitUpload(
                         dequeued.Id, rawUnit, startedAt, populated,
                         status, note ?? "", analysisErrors, analysisSummary);

                    swDbLog.Stop();
                }
            }

            await _logBuffer.Flush();

            _logger.LogWarning($"End Total {swCycle.Elapsed};{Environment.NewLine} Parse {swParseFile.Elapsed} {Environment.NewLine} Populate {swPopulation.Elapsed} {Environment.NewLine} Analyze {swAnalyze.Elapsed} {Environment.NewLine} SaveUnit {swSave.Elapsed} {Environment.NewLine} Logging {swDbLog.Elapsed} {Environment.NewLine}");
            _logger.LogWarning($"End Average {Environment.NewLine} Populate {(double)swPopulation.Elapsed.Seconds / populationCount} s {Environment.NewLine} Analyze {(double)swAnalyze.Elapsed.Seconds / analyzeCount} s {Environment.NewLine} SaveUnit {(double)swSave.Elapsed.Seconds / saveCount} s {Environment.NewLine} Logging {(double)swDbLog.Elapsed.Seconds / dbLogCount}");

            await _queueSvc.FinishQueueItem(
                dequeued,
                anyWarnings
                    ? QueueStatus.DataLoadCompletedPartially
                    : QueueStatus.DataLoadCompleted);
        }

        /// <summary>
        /// Method exception handler
        /// </summary>
        public void OnException(Exception ex) => _logger.LogError(ex.Message);

        private async Task<(string error, DataSourceQueue result)> Dequeue()
        {
            DataSourceQueue queueItem;
            try
            {
                queueItem = await _queueSvc.Dequeue();
            }
            catch (Exception ex)
            {
                return (ex.Message, null);
            }
            return (null, queueItem);
        }

        private static async Task<(string error, IReadOnlyDictionary<string, object>[] result)> ParseFile(DataSourceQueue queueItem)
        {
            IEnumerable<IReadOnlyDictionary<string, object>> parsed;
            try
            {
                switch (queueItem.DataSourceFileName)
                {
                    case string name when name.EndsWith(".xml", StringComparison.OrdinalIgnoreCase):
                        parsed = await FileParser.GetRawEntitiesFromXml(queueItem.DataSourcePath, queueItem.DataSource.VariablesMappingArray);
                        break;
                    case string name when name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase):
                        parsed = await FileParser.GetRawEntitiesFromCsv(
                            queueItem.DataSourcePath,
                            queueItem.DataSource.CsvSkipCount,
                            queueItem.DataSource.CsvDelimiter,
                            queueItem.DataSource.VariablesMappingArray);
                        break;
                    default: return ("Unsupported type of file", null);
                }
            }
            catch (Exception ex)
            {
                return (ex.Message, null);
            }

            var parsedArr = parsed.ToArray();

            if (parsedArr.Length == 0)
            {
                return (Resource.UploadFileEmpty, parsedArr);
            }

            if (parsedArr.Any(x => x.Count == 0))
            {
                return (Resource.FileHasEmptyUnit, parsedArr);
            }
            return (null, parsedArr);
        }

        private (string , (IReadOnlyDictionary<string, string[]>, string[] test)) AnalyzeUnit(IStatisticalUnit unit, DataSourceQueue queueItem)
        {
            if (queueItem.DataSource.DataSourceUploadType != DataSourceUploadTypes.StatUnits)
                return (null, (new Dictionary<string, string[]>(), new string[0]));

            AnalysisResult analysisResult;
            try
            {
                analysisResult = _analysisSvc.AnalyzeStatUnit(unit, queueItem.DataSource.AllowedOperations == DataSourceAllowedOperation.Alter, true, false);
            }
            catch (Exception ex)
            {
                return (ex.Message, (null, null));
            }
            return (null, (
                analysisResult.Messages,
                analysisResult.SummaryMessages?.ToArray() ?? Array.Empty<string>()));
        }

        /// <summary>
        /// Делает копию файла с удалением пустых строк
        /// </summary>
        /// <param name="item"></param>
        /// <returns></returns>
        private async Task<string> MutateFileAsync(DataSourceQueue item)
        {
            var rawLines = await GetRawFileAsync(item);
            try
            {
                await WriteFileAsync(string.Join("\r\n", rawLines.Where(c => !string.IsNullOrEmpty(c))), item.DataSourcePath);
            }
            catch (Exception ex)
            {
                return ex.Message;
            }
            return string.Empty;
        }

        private async Task<string[]> GetRawFileAsync(DataSourceQueue item)
        {
            if (item.DataSource == null) throw new Exception(Resource.DataSourceNotFound);
            var i = item.DataSource.CsvSkipCount;
            string rawLines;
            if (!File.Exists(item.DataSourcePath)) throw new FileNotFoundException(Resource.FileDoesntExistOrInQueue);
            using (var stream = File.OpenRead(item.DataSourcePath))
            using (var reader = new StreamReader(stream))
            {
                while (--i == 0) await reader.ReadLineAsync();
                rawLines = await reader.ReadToEndAsync();
            }

            return rawLines.Split('\r', '\n');
        }

        private async Task WriteFileAsync(string csv, string path) => await File.WriteAllTextAsync(path, csv);
    }
}
