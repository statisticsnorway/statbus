using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Business;
using nscreg.Data;
using nscreg.Server.DataUploadSvc.Interfaces;
using nscreg.Services.DataSources;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.DataUploadSvc.Jobs
{
    internal class QueueJob : IJob
    {
        public int Interval { get; }
        private readonly QueueService _queueSvc;

        private readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>> _createByType;
        private readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>> _updateByType;

        public QueueJob(NSCRegDbContext ctx, int dequeueInterval)
        {
            Interval = dequeueInterval;
            _queueSvc = new QueueService(ctx);

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
            var queueItem = await _queueSvc.Dequeue();

            IEnumerable<IReadOnlyDictionary<string, string>> rawEntities;
            switch (queueItem.DataSourceFileName)
            {
                case var str when str.EndsWith(".xml", StringComparison.Ordinal):
                    rawEntities = FileParser.GetRawEntitiesFromXml(queueItem.DataSourceFileName);
                    break;
                case var str when str.EndsWith(".csv", StringComparison.Ordinal):
                    rawEntities = await FileParser.GetRawEntitiesFromCsv(queueItem.DataSourceFileName);
                    break;
                default:
                    throw new Exception("unknown data source type");
            }

            var untrustedItemEncountered = false;

            foreach (var rawEntity in rawEntities)
            {
                var parsedUnit = await _queueSvc.GetStatUnitFromRawEntity(
                    rawEntity,
                    queueItem.DataSource.StatUnitType,
                    queueItem.DataSource.VariablesMappingArray);

                // TODO: field type should not be just a string
                parsedUnit.DataSource = queueItem.DataSource.Id.ToString();

                var issues = Analysis.Analyze(parsedUnit);
                if (!issues.Any())
                {
                    var unitExists =
                        await _queueSvc.CheckIfUnitExists(queueItem.DataSource.StatUnitType, parsedUnit.StatId);
                    var sureSave = queueItem.DataSource.Priority == DataSourcePriority.Trusted
                                   || queueItem.DataSource.Priority == DataSourcePriority.Ok && !unitExists;

                    DataUploadingLogStatuses logStatus;
                    var note = string.Empty;
                    var uploadStartedDate = DateTime.Now;
                    if (sureSave)
                    {
                        var saveAction = unitExists
                            ? _updateByType[queueItem.DataSource.StatUnitType]
                            : _createByType[queueItem.DataSource.StatUnitType];
                        try
                        {
                            await saveAction(parsedUnit, queueItem.UserId);
                            logStatus = DataUploadingLogStatuses.Done;
                        }
                        catch (Exception ex)
                        {
                            note = ex.Message;
                            logStatus = DataUploadingLogStatuses.Error;
                        }
                    }
                    else
                    {
                        if (!untrustedItemEncountered) untrustedItemEncountered = true;
                        logStatus = DataUploadingLogStatuses.Warning;
                    }

                    var uploadEndedDate = DateTime.Now;
                    await _queueSvc.LogStatUnitUpload(
                        queueItem,
                        parsedUnit,
                        rawEntity.Values,
                        uploadStartedDate,
                        uploadEndedDate,
                        logStatus,
                        note);
                }
                else
                {
                    // TODO: upload log record with error message? collect errors from analyze results?
                }
            }

            await _queueSvc.FinishQueueItem(queueItem, untrustedItemEncountered);
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
