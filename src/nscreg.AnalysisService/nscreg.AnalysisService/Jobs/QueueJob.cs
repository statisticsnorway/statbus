using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.AnalysisService.Interfaces;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Services.DataSources;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Services.Analysis.StatUnit;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.AnalysisService.Jobs
{
    internal class QueueJob : IJob
    {
        public int Interval { get; }
        private readonly QueueService _queueSvc;
        private readonly IStatUnitAnalyzeService _analysisService;

        private readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>> _createByType;
        private readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>> _updateByType;

        private (
            DataSourceQueue queueItem,
            IStatisticalUnit parsedUnit,
            IEnumerable<string> rawValues,
            DateTime? uploadStartedDate) _state;

        public QueueJob(NSCRegDbContext ctx, int dequeueInterval)
        {
            Interval = dequeueInterval;
            _queueSvc = new QueueService(ctx);
            var analyzer = new StatUnitAnalyzer(new Dictionary<StatUnitMandatoryFieldsEnum, bool>(),
                new Dictionary<StatUnitConnectionsEnum, bool>(), new Dictionary<StatUnitOrphanEnum, bool>());
            _analysisService = new StatUnitAnalyzeService(ctx, analyzer);

            var createSvc = new CreateService(ctx);
            _createByType = new Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId)
                    => createSvc.CreateLegalUnit(MapUnitToModel<LegalUnitCreateM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId)
                    => createSvc.CreateLocalUnit(MapUnitToModel<LocalUnitCreateM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId)
                    => createSvc.CreateEnterpriseUnit(MapUnitToModel<EnterpriseUnitCreateM>(unit), userId),
                [StatUnitTypes.EnterpriseGroup] = (unit, userId)
                    => createSvc.CreateEnterpriseGroup(MapUnitToModel<EnterpriseGroupCreateM>(unit), userId),
            };

            var editSvc = new EditService(ctx);
            _updateByType = new Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId)
                    => editSvc.EditLegalUnit(MapUnitToModel<LegalUnitEditM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId)
                    => editSvc.EditLocalUnit(MapUnitToModel<LocalUnitEditM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId)
                    => editSvc.EditEnterpriseUnit(MapUnitToModel<EnterpriseUnitEditM>(unit), userId),
                [StatUnitTypes.EnterpriseGroup] = (unit, userId)
                    => editSvc.EditEnterpriseGroup(MapUnitToModel<EnterpriseGroupEditM>(unit), userId),
            };

            T MapUnitToModel<T>(IStatisticalUnit unit) => Mapper.Map<T>(unit);
        }

        public async void Execute(CancellationToken cancellationToken)
        {
            _state.queueItem = await _queueSvc.Dequeue();
            if (_state.queueItem == null) return;

            IEnumerable<IReadOnlyDictionary<string, string>> rawEntities;
            {
                var path = _state.queueItem.DataSourcePath;
                switch (_state.queueItem.DataSourceFileName)
                {
                    case var str when str.EndsWith(".xml", StringComparison.Ordinal):
                        rawEntities = FileParser.GetRawEntitiesFromXml(path);
                        break;
                    case var str when str.EndsWith(".csv", StringComparison.Ordinal):
                        rawEntities = await FileParser.GetRawEntitiesFromCsv(path);
                        break;
                    default:
                        throw new Exception("unknown data source type");
                }
            }

            var unitType = _state.queueItem.DataSource.StatUnitType;
            var priority = _state.queueItem.DataSource.Priority;
            var hasWarnings = false;

            foreach (var rawEntity in rawEntities)
            {
                _state.rawValues = rawEntity.Values;
                _state.parsedUnit = await _queueSvc.GetStatUnitFromRawEntity(
                    rawEntity,
                    unitType,
                    _state.queueItem.DataSource.VariablesMappingArray);

                _state.parsedUnit.DataSource = _state.queueItem.DataSourceFileName;

                var uploadStartedDate = DateTime.Now;
                DataUploadingLogStatuses logStatus;
                var note = string.Empty;
                var issues = _analysisService.AnalyzeStatUnit(_state.parsedUnit);

                if (issues.Any())
                {
                    hasWarnings = true;
                    logStatus = DataUploadingLogStatuses.Error;
                    note = string.Join(", ", issues.Select((key, value) => $"{key}: {value}"));
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

                await _queueSvc.LogStatUnitUpload(
                    _state.queueItem,
                    _state.parsedUnit,
                    _state.rawValues,
                    uploadStartedDate,
                    DateTime.Now,
                    logStatus,
                    note);

                _state = (_state.queueItem, null, null, null);
            }

            await _queueSvc.FinishQueueItem(_state.queueItem, hasWarnings);
            _state.queueItem = null;
        }

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
