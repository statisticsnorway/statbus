using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Internal;
using Microsoft.Extensions.Logging;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using Newtonsoft.Json;
using QueueStatus = nscreg.Data.Constants.DataSourceQueueStatuses;
using LogStatus = nscreg.Data.Constants.DataUploadingLogStatuses;

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
        private AnalyzeService _analysisSvc;
        private SaveManager _saveManager;

        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly ValidationSettings _validationSettings;
        private NSCRegDbContext _context;
        public QueueJob(
            int dequeueInterval,
            ILogger logger,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields,
            ValidationSettings validationSettings)
        {
            _logger = logger;
            Interval = dequeueInterval;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _dbMandatoryFields = dbMandatoryFields;
            _validationSettings = validationSettings;
            AddScopedServices();
        }

        private void AddScopedServices()
        {
            var dbContextHelper = new DbContextHelper();
            _context = dbContextHelper.CreateDbContext(new string[] { });
            _queueSvc = new QueueService(_context);
            _analysisSvc = new AnalyzeService(_context, _statUnitAnalysisRules, _dbMandatoryFields, _validationSettings);
            var createSvc = new CreateService(_context, _statUnitAnalysisRules, _dbMandatoryFields, _validationSettings, StatUnitTypeOfSave.Service);
            var editSvc = new EditService(_context, _statUnitAnalysisRules, _dbMandatoryFields, _validationSettings);
            _saveManager = new SaveManager(_context, _queueSvc, createSvc, editSvc);
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

            _logger.LogInformation("parsing queue entry #{0}", dequeued.Id);
            var (parseError, parsed) = await ParseFile(dequeued);
            if (parseError.HasValue())
            {
                _logger.LogInformation("finish queue item with error: {0}", parseError);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, parseError);
                return;
            }

            _logger.LogInformation("parsed {0} entities", parsed.Length);

            var anyWarnings = false;

            for (var i = 0; i < parsed.Length; i++)
            {
                _logger.LogInformation("processing entity #{0}", i + 1);
                var startedAt = DateTime.Now;

                _logger.LogInformation("populating unit");

                var (populateError, populated) = await PopulateUnit(dequeued, parsed[i]);
                if (populateError.HasValue())
                {
                    _logger.LogInformation("error during populating of unit: {0}", populateError);
                    anyWarnings = true;
                    await LogUpload(LogStatus.Error, populateError);
                    continue;
                }

                if (dequeued.DataSource.AllowedOperations == DataSourceAllowedOperation.Alter)
                {
                    if (!string.IsNullOrWhiteSpace(populated.StatId) && !_analysisSvc.CheckStatUnitIdIsContains(populated))
                    {
                        _logger.LogInformation("StatUnit failed with error: {0} ({1})", Resource.StatUnitIdIsNotFound, populated.StatId);
                        anyWarnings = true;
                        await LogUpload(LogStatus.Error, nameof(Resource.StatUnitIdIsNotFound));
                        continue;
                    }
                }

                _logger.LogInformation(
                    "analyzing populated unit #{0}",
                    populated.RegId > 0 ? populated.RegId.ToString() : "(new)");
                var (analysisError, (errors, summary)) = AnalyzeUnit(populated, dequeued);
                if (analysisError.HasValue())
                {
                    _logger.LogInformation("analysis attempt failed with error: {0}", analysisError);
                    anyWarnings = true;
                    await LogUpload(LogStatus.Error, analysisError);
                    continue;
                }
                if (errors.Count > 0)
                {
                    _logger.LogInformation("analysis revealed {0} errors", errors.Count);
                    errors.Values.ForEach(x=>x.ForEach(e=> _logger.LogInformation(Resource.ResourceManager.GetString(e.ToString()))));
                    anyWarnings = true;
                    await LogUpload(LogStatus.Warning,  string.Join(",", errors.SelectMany(c => c.Value)), errors, summary);
                    continue;
                }

                _logger.LogInformation("saving unit");
                var (saveError, saved) = await _saveManager.SaveUnit(populated, dequeued.DataSource, dequeued.UserId);
                if (saveError.HasValue())
                {
                    _logger.LogError(saveError);
                    anyWarnings = true;
                    await LogUpload(LogStatus.Warning, saveError);
                    continue;
                }

                if (!saved) anyWarnings = true;
                await LogUpload(saved ? LogStatus.Done : LogStatus.Warning);

                Task LogUpload(LogStatus status, string note = "",
                    IReadOnlyDictionary<string, string[]> analysisErrors = null,
                    IEnumerable<string> analysisSummary = null)
                {
                    var rawUnit = JsonConvert.SerializeObject(
                        dequeued.DataSource.VariablesMappingArray.ToDictionary(
                            x => x.target,
                            x =>
                            {
                                if (parsed[i] is string)
                                    return parsed[i][x.source];
                                var tmp = x.source.Split('.');
                                if (parsed[i].ContainsKey(tmp[0]))
                                    return JsonConvert.SerializeObject(parsed[i][tmp[0]]);
                                return tmp[0];
                            }));
                    return _queueSvc.LogUnitUpload(
                        dequeued, rawUnit, startedAt, populated, DateTime.Now,
                        status, note ?? "", analysisErrors, analysisSummary);
                }
            }

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
                    case var name when name.EndsWith(".xml", StringComparison.OrdinalIgnoreCase):
                        parsed = FileParser.GetRawEntitiesFromXml(queueItem.DataSourcePath);
                        break;
                    case var name when name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase):
                        parsed = await FileParser.GetRawEntitiesFromCsv(
                            queueItem.DataSourcePath,
                            queueItem.DataSource.CsvSkipCount,
                            queueItem.DataSource.CsvDelimiter);
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
            return  (null, parsedArr);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="queueItem"></param>
        /// <param name="parsedUnit"></param>
        /// <returns></returns>
        private async Task<(string, StatisticalUnit)> PopulateUnit(
            DataSourceQueue queueItem,
            IReadOnlyDictionary<string, object> parsedUnit)
        {
            StatisticalUnit unit;

            try
            {
                unit = await _queueSvc.GetStatUnitFromRawEntity(
                    parsedUnit,
                    queueItem.DataSource.StatUnitType,
                    queueItem.DataSource.VariablesMappingArray,
                    queueItem.DataSource.DataSourceUploadType,
                    queueItem.DataSource.AllowedOperations);
            }
            catch (Exception ex)
            {
                var data = ex.Data.Keys
                    .Cast<string>()
                    .Where(key => key != "unit")
                    .Select(key => $"`{key}` = `{ex.Data[key]}`");
                return (ex.Message,
                    ex.Data["unit"] as StatisticalUnit);
            }

            unit.DataSource = queueItem.DataSourceFileName;
            unit.ChangeReason = ChangeReasons.Edit;
            unit.EditComment = "Uploaded from data source file";
            return (null, unit);
        }

        private (string, (IReadOnlyDictionary<string, string[]>, string[])) AnalyzeUnit(IStatisticalUnit unit, DataSourceQueue queueItem)
        {
            if(queueItem.DataSource.DataSourceUploadType != DataSourceUploadTypes.StatUnits)
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
        private async Task<string> MutateFileAsync(DataSourceQueue item)
        {
            var rawLines = await GetRawFileAsync(item);
            var dataSource = await _context.DataSources.FirstOrDefaultAsync(c => c.Id == item.DataSourceId);
            if(dataSource != null)
            {
                try
                {
                    var attrToCheck = dataSource.AttributesToCheckArray.ToArray();
                    var originalAttr = dataSource.OriginalAttributesArray.ToArray();
                    var arrayHeaders = rawLines[0].Split(item.DataSource.CsvDelimiter);
                    rawLines[0] = string.Join(item.DataSource.CsvDelimiter,
                        arrayHeaders.Select(c => c.Replace(c,
                            c == originalAttr.FirstOrDefault(x => x == c)
                                ? attrToCheck.ElementAtOrDefault(originalAttr.IndexOf(c))
                                : c)));
                    await WriteFileAsync(string.Join("\r\n",rawLines.Where(c => !string.IsNullOrEmpty(c))), item.DataSourcePath);
                }
                catch(Exception ex)
                {
                    return ex.Message;
                }
            }
            else
            {
                return Resource.DataSourceNotFound;
            }

            return string.Empty;

        }
        private async Task<string[]> GetRawFileAsync(DataSourceQueue item)
        {
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
