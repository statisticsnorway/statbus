using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using nscreg.Resources.Languages;

namespace nscreg.Server.DataUploadSvc.Jobs
{
    /// <summary>
    /// Класс работы очереди
    /// </summary>
    internal class QueueJob : IJob
    {
        private readonly ILogger _logger;
        public int Interval { get; }
        private readonly QueueService _queueSvc;
        private readonly IStatUnitAnalyzeService _analysisService;

        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _createByType;
        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _updateByType;

        private (
            DataSourceQueue queueItem,
            StatisticalUnit parsedUnit,
            IEnumerable<string> rawValues,
            DateTime? uploadStartedDate) _state;

        public QueueJob(NSCRegDbContext ctx, int dequeueInterval, ILogger logger, StatUnitAnalysisRules statUnitAnalysisRules, DbMandatoryFields dbMandatoryFields)
        {
            _logger = logger;
            Interval = dequeueInterval;
            _queueSvc = new QueueService(ctx);
            _analysisService = new AnalyzeService(ctx, statUnitAnalysisRules, dbMandatoryFields);

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
            _logger.LogInformation("executing main job...");
            _state.queueItem = await _queueSvc.Dequeue();
            if (_state.queueItem == null) return;
            _logger.LogInformation("dequeued item {0}", _state.queueItem);

            IReadOnlyDictionary<string, string>[] rawEntities;
            {
                var path = _state.queueItem.DataSourcePath;
                switch (_state.queueItem.DataSourceFileName)
                {
                    case var str when str.EndsWith(".xml", StringComparison.Ordinal):
                        rawEntities = FileParser.GetRawEntitiesFromXml(path).ToArray();
                        break;
                    case var str when str.EndsWith(".csv", StringComparison.Ordinal):
                        rawEntities =
                        (await FileParser.GetRawEntitiesFromCsv(
                            path, _state.queueItem.DataSource.CsvSkipCount,
                            _state.queueItem.DataSource.CsvDelimiter)).ToArray();
                        break;
                    default:
                        throw new Exception("unknown data source type");
                }
            }
            _logger.LogInformation($"parsed {rawEntities.Length} entities");

            var unitType = _state.queueItem.DataSource.StatUnitType;
            var priority = _state.queueItem.DataSource.Priority;
            var hasWarnings = false;

            foreach (var rawEntity in rawEntities)
            {
                _state.rawValues = rawEntity.Values;
                _logger.LogInformation("processing raw entity {0}", rawEntity);

                _state.parsedUnit = await _queueSvc.GetStatUnitFromRawEntity(
                    rawEntity,
                    unitType,
                    _state.queueItem.DataSource.VariablesMappingArray);

                _state.parsedUnit.DataSource = _state.queueItem.DataSourceFileName;
                _state.parsedUnit.ChangeReason = ChangeReasons.Edit;
                _state.parsedUnit.EditComment = "data upload job";
                _state.parsedUnit.Status = StatUnitStatuses.Active;

                _logger.LogInformation("initialized as {0}", _state.parsedUnit);

                _state.uploadStartedDate = DateTime.Now;
                DataUploadingLogStatuses logStatus;
                var note = string.Empty;
                var issues = _analysisService.AnalyzeStatUnit(_state.parsedUnit);

                if (issues.Messages.Any())
                {
                    _logger.LogInformation("analyzed, found issues: {0}", issues);
                    hasWarnings = true;
                    logStatus = DataUploadingLogStatuses.Error;
                    note = nameof(Resource.HasAnalysisError);
                }
                else
                {
                    var unitExists = await _queueSvc.CheckIfUnitExists(unitType, _state.parsedUnit.StatId);
                    if (priority == DataSourcePriority.Trusted ||
                        priority == DataSourcePriority.Ok && !unitExists)
                    {
                        var saveAction = unitExists
                            ? _updateByType[unitType]
                            : _createByType[unitType];
                        _logger.LogInformation(unitExists ? "updating unit {0}" : "creating unit {0}", _state.parsedUnit);
                        try
                        {
                            await saveAction(_state.parsedUnit, _state.queueItem.UserId);
                            logStatus = DataUploadingLogStatuses.Done;
                        }
                        catch (Exception ex)
                        {
                            hasWarnings = true;
                            logStatus = DataUploadingLogStatuses.Error;
                            note = ex.Message;
                        }
                    }
                    else
                    {
                        hasWarnings = true;
                        logStatus = DataUploadingLogStatuses.Warning;
                    }
                }

                _logger.LogInformation(
                    "log upload info: started {0}, status {1}, note {2}",
                    _state.uploadStartedDate.ToString(), logStatus, note);
                await _queueSvc.LogStatUnitUpload(
                    _state.queueItem,
                    _state.parsedUnit,
                    _state.rawValues,
                    _state.uploadStartedDate,
                    DateTime.Now,
                    logStatus,
                    note,
                    issues.Messages,
                    issues.SummaryMessages);

                _state = (_state.queueItem, null, null, null);
            }

            _logger.LogInformation(
                "updating queue item: {0}, has warnings? {1}",
                _state.queueItem, hasWarnings);
            await _queueSvc.FinishQueueItem(_state.queueItem, hasWarnings);
            _state.queueItem = null;
        }

        /// <summary>
        /// Метод обработчик исключений
        /// </summary>
        public async void OnException(Exception e)
        {
            if (_state.queueItem == null) return;
            await _queueSvc.LogStatUnitUpload(
                _state.queueItem,
                _state.parsedUnit,
                _state.rawValues,
                _state.uploadStartedDate,
                DateTime.Now,
                DataUploadingLogStatuses.Error,
                e.Message);
            await _queueSvc.FinishQueueItem(_state.queueItem, true);
        }
    }
}
