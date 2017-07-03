using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Server.DataUploadSvc.Interfaces;
using nscreg.Services.DataSources;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Services.StatUnit;
using static nscreg.Server.DataUploadSvc.Jobs.ModelHelpers;

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
            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());
            _queueSvc = new QueueService(ctx);

            var createSvc = new CreateService(ctx);
            _createByType = new Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId) => createSvc.CreateLegalUnit(MapUnitTo<LegalUnitCreateM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId) => createSvc.CreateLocalUnit(MapUnitTo<LocalUnitCreateM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId) => createSvc.CreateEnterpriseUnit(MapUnitTo<EnterpriseUnitCreateM>(unit), userId),
                [StatUnitTypes.EnterpriseGroup] = (unit, userId) => createSvc.CreateEnterpriseGroup(MapUnitTo<EnterpriseGroupCreateM>(unit), userId),
            };

            var editSvc = new EditService(ctx);
            _updateByType = new Dictionary<StatUnitTypes, Func<IStatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId) => editSvc.EditLegalUnit(MapUnitTo<>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId) => editSvc.EditLocalUnit(MapUnitTo<>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId) => editSvc.EditEnterpriseUnit(MapUnitTo<>(unit), userId),
                [StatUnitTypes.EnterpriseGroup] = (unit, userId) => editSvc.EditEnterpriseGroup(MapUnitTo(unit), userId),
            };
        }

        public async void Execute(CancellationToken cancellationToken)
        {
            var queueItem = await _queueSvc.Dequeue();

            IEnumerable<IReadOnlyDictionary<string, string>> rawEntities;
            switch (queueItem.DataSourceFileName)
            {
                case var str when str.EndsWith(".xml", StringComparison.Ordinal):
                    rawEntities = await FileParser.GetRawEntitiesFromXml(queueItem.DataSourceFileName);
                    break;
                case var str when str.EndsWith(".csv", StringComparison.Ordinal):
                    rawEntities = await FileParser.GetRawEntitiesFromCsv(queueItem.DataSourceFileName);
                    break;
                default:
                    // TODO: throw excetion if unknown file type?
                    throw new Exception("unknown data source type");
            }

            var untrustedItemEncountered = false;

            foreach (var rawEntity in rawEntities)
            {
                var parsedUnit = await _queueSvc.GetStatUnitFromRawEntity(
                    rawEntity,
                    queueItem.DataSource.StatUnitType,
                    queueItem.DataSource.VariablesMappingArray);

                var unitIsBrandNew = string.IsNullOrEmpty(parsedUnit.StatId);
                var sureSave = queueItem.DataSource.Priority == DataSourcePriority.Trusted
                    || queueItem.DataSource.Priority == DataSourcePriority.Ok && unitIsBrandNew;

                DataUploadingLogStatuses logStatus;
                var note = string.Empty;
                var uploadStartedDate = DateTime.Now;
                if (sureSave)
                {
                    var saveAction = unitIsBrandNew
                        ? _createByType[queueItem.DataSource.StatUnitType]
                        : _updateByType[queueItem.DataSource.StatUnitType];
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
                    uploadStartedDate,
                    uploadEndedDate,
                    logStatus,
                    note);
            }

            await _queueSvc.FinishQueueItem(queueItem, untrustedItemEncountered);
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
