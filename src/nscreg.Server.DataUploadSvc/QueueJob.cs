using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
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
using RawUnit = System.Collections.Generic.IReadOnlyDictionary<string, string>;
using QueueStatus = nscreg.Data.Constants.DataSourceQueueStatuses;
using LogStatus = nscreg.Data.Constants.DataUploadingLogStatuses;

namespace nscreg.Server.DataUploadSvc
{
    /// <summary>
    /// Класс работы очереди
    /// </summary>
    internal class QueueJob : IJob
    {
        private readonly ILogger _logger;
        public int Interval { get; }
        private readonly QueueService _queueSvc;
        private readonly AnalyzeService _analysisSvc;
        private readonly SaveManager _saveManager;
        private readonly IReadOnlyDictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _createByType;
        private readonly IReadOnlyDictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _updateByType;
        private readonly NSCRegDbContext _ctx;

        public QueueJob(
            NSCRegDbContext ctx,
            int dequeueInterval,
            ILogger logger,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields,
            ValidationSettings validationSettings)
        {
            _ctx = ctx;
            _logger = logger;
            Interval = dequeueInterval;
            _queueSvc = new QueueService(ctx);
            _analysisSvc = new AnalyzeService(ctx, statUnitAnalysisRules, dbMandatoryFields, validationSettings);

            var createSvc = new CreateService(ctx, statUnitAnalysisRules, dbMandatoryFields, validationSettings);
            var editSvc = new EditService(ctx, statUnitAnalysisRules, dbMandatoryFields, validationSettings);
            _saveManager = new SaveManager(ctx, _queueSvc, createSvc, editSvc);
        }

        /// <summary>
        /// Метод выполнения работы очереди
        /// </summary>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.LogInformation("dequeue attempt...");
            var (dequeueError, dequeued) = await Dequeue();
            if (dequeueError.HasValue())
            {
                _logger.LogInformation("dequeue failed with error: {0}", dequeueError);
                return;
            }
            if (dequeued == null) return;

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
                    await LogUpload(LogStatus.Warning, "ErrorsOccuredDuringManualAnalysis", errors, summary);
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
                            x => parsed[i][x.source]));
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
        /// Метод обработчик исключений
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

        private static async Task<(string error, RawUnit[] result)> ParseFile(DataSourceQueue queueItem)
        {
            IEnumerable<RawUnit> parsed;
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

        private async Task<(string, StatisticalUnit)> PopulateUnit(
            DataSourceQueue queueItem,
            IReadOnlyDictionary<string, string> parsedUnit)
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
                return (
                    $"message: {ex.Message}, data: {string.Join(", ", data)}",
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
                analysisResult = _analysisSvc.AnalyzeStatUnit(unit);
            }
            catch (Exception ex)
            {
                return (ex.Message, (null, null));
            }
            return (null, (
                analysisResult.Messages,
                analysisResult.SummaryMessages?.ToArray() ?? Array.Empty<string>()));
        }
    }
}
