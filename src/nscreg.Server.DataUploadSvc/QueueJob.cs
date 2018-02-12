using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.Extensions.Logging;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using Newtonsoft.Json;
using RawUnit = System.Collections.Generic.IReadOnlyDictionary<string, string>;
using QueueStatus = nscreg.Data.Constants.DataSourceQueueStatuses;
using LogStatus = nscreg.Data.Constants.DataUploadingLogStatuses;
using Priority = nscreg.Data.Constants.DataSourcePriority;

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
        private readonly IReadOnlyDictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _createByType;
        private readonly IReadOnlyDictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _updateByType;

        public QueueJob(
            NSCRegDbContext ctx,
            int dequeueInterval,
            ILogger logger,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields)
        {
            _logger = logger;
            Interval = dequeueInterval;
            _queueSvc = new QueueService(ctx);
            _analysisSvc = new AnalyzeService(ctx, statUnitAnalysisRules, dbMandatoryFields);

            var createSvc = new CreateService(ctx, statUnitAnalysisRules, dbMandatoryFields);
            _createByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId) =>
                    createSvc.CreateLegalUnit(Mapper.Map<LegalUnitCreateM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId) =>
                    createSvc.CreateLocalUnit(Mapper.Map<LocalUnitCreateM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId) =>
                    createSvc.CreateEnterpriseUnit(Mapper.Map<EnterpriseUnitCreateM>(unit), userId),
            };

            var editSvc = new EditService(ctx, statUnitAnalysisRules, dbMandatoryFields);
            _updateByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId) =>
                    editSvc.EditLegalUnit(Mapper.Map<LegalUnitEditM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId) =>
                    editSvc.EditLocalUnit(Mapper.Map<LocalUnitEditM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId) =>
                    editSvc.EditEnterpriseUnit(Mapper.Map<EnterpriseUnitEditM>(unit), userId),
            };
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
            _logger.LogInformation("parsed {0} entities", parsed.Length + 1);

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
                var (analysisError, (errors, summary)) = AnalyzeUnit(populated);
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
                    anyWarnings = true;
                    await LogUpload(LogStatus.Warning, "Errors occured during manual analysis", errors, summary);
                    continue;
                }

                _logger.LogInformation("saving unit");
                var (saveError, saved) = await SaveUnit(
                    populated, dequeued.DataSource.StatUnitType,
                    dequeued.DataSource.Priority, dequeued.UserId);
                if (saveError.HasValue())
                {
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
                        status, note, analysisErrors, analysisSummary);
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

            return (null, parsed.ToArray());
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
                    queueItem.DataSource.VariablesMappingArray);
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
            unit.Status = StatUnitStatuses.Active;
            return (null, unit);
        }

        private (string, (IReadOnlyDictionary<string, string[]>, string[])) AnalyzeUnit(IStatisticalUnit unit)
        {
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

        private async Task<(string, bool)> SaveUnit(
            StatisticalUnit parsedUnit,
            StatUnitTypes unitType,
            Priority priority,
            string userId)
        {
            var unitExists = await _queueSvc.CheckIfUnitExists(unitType, parsedUnit.StatId);

            if (priority != Priority.Trusted && (priority != Priority.Ok || unitExists))
                return (null, false);

            var saveAction = unitExists ? _updateByType[unitType] : _createByType[unitType];

            try
            {
                await saveAction(parsedUnit, userId);
            }
            catch (Exception ex)
            {
                return (ex.Message, false);
            }
            return (null, true);
        }
    }
}
