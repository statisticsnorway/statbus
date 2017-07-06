using System;
using System.Collections.Generic;
using nscreg.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using static nscreg.Business.DataSources.StatUnitKeyValueParser;

namespace nscreg.Services.DataSources
{
    public class QueueService
    {
        private readonly NSCRegDbContext _ctx;

        private readonly Dictionary<StatUnitTypes, IQueryable<IStatisticalUnit>> _getStatUnitSet;

        // TODO: use new TUnit()?
        private static readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit>> CreateByType
            = new Dictionary<StatUnitTypes, Func<IStatisticalUnit>>
            {
                [StatUnitTypes.LocalUnit] = () => new LocalUnit(),
                [StatUnitTypes.LegalUnit] = () => new LegalUnit(),
                [StatUnitTypes.EnterpriseUnit] = () => new EnterpriseUnit(),
                [StatUnitTypes.EnterpriseGroup] = () => new EnterpriseGroup(),
            };

        public QueueService(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            _getStatUnitSet = new Dictionary<StatUnitTypes, IQueryable<IStatisticalUnit>>
            {
                [StatUnitTypes.LocalUnit] = _ctx.LocalUnits
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region)
                    .Include(x => x.PersonsUnits),
                [StatUnitTypes.LegalUnit] = _ctx.LegalUnits
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region)
                    .Include(x => x.PersonsUnits),
                [StatUnitTypes.EnterpriseUnit] = _ctx.EnterpriseUnits
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region)
                    .Include(x => x.PersonsUnits),
                [StatUnitTypes.EnterpriseGroup] = _ctx.EnterpriseGroups
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region),
            };
        }

        public async Task<DataSourceQueue> Dequeue()
        {
            var queueItem = _ctx.DataSourceQueues
                .Include(item => item.DataSource)
                .Include(item => item.DataUploadingLogs)
                .FirstOrDefault(item => item.Status == DataSourceQueueStatuses.InQueue);

            if (queueItem == null) return null;

            queueItem.StartImportDate = DateTime.Now;
            queueItem.Status = DataSourceQueueStatuses.Loading;
            await _ctx.SaveChangesAsync();

            _ctx.Entry(queueItem).State = EntityState.Detached;
            return queueItem;
        }

        public async Task<IStatisticalUnit> GetStatUnitFromRawEntity(
            IReadOnlyDictionary<string, string> raw,
            StatUnitTypes unitType,
            IEnumerable<(string source, string target)> propMapping)
        {
            var mapping = propMapping as (string source, string target)[] ?? propMapping.ToArray();

            var resultUnit = await GetStatUnitBase();

            ParseAndMutateStatUnit(
                mapping.ToDictionary(x => x.source, x => x.target),
                raw,
                resultUnit);

            return resultUnit;

            async Task<IStatisticalUnit> GetStatUnitBase()
            {
                IStatisticalUnit existing = null;
                if (raw.TryGetValue(GetStatIdSourceKey(mapping), out string statId))
                    existing = await _getStatUnitSet[unitType]
                        .SingleOrDefaultAsync(x => x.StatId == statId && !x.ParrentId.HasValue);

                if (existing == null) return CreateByType[unitType]();

                _ctx.Entry(existing).State = EntityState.Detached;
                return existing;
            }
        }

        public async Task LogStatUnitUpload(
            DataSourceQueue queueItem,
            IStatisticalUnit unit,
            IEnumerable<string> props,
            DateTime started,
            DateTime ended,
            DataUploadingLogStatuses status,
            string note)
        {
            _ctx.DataSourceQueues.Attach(queueItem);
            if (queueItem.DataUploadingLogs == null)
                queueItem.DataUploadingLogs = new List<DataUploadingLog>();
            queueItem.DataUploadingLogs.Add(new DataUploadingLog
            {
                TargetStatId = unit.StatId,
                StatUnitName = unit.Name,
                SerializedUnit = SerializeToString(unit, props),
                StartImportDate = started,
                EndImportDate = ended,
                Status = status,
                Note = note,
            });
            await _ctx.SaveChangesAsync();
            _ctx.Entry(queueItem).State = EntityState.Detached;
        }

        public async Task FinishQueueItem(DataSourceQueue queueItem, bool untrustedEntitiesEncountered)
        {
            _ctx.DataSourceQueues.Attach(queueItem);
            queueItem.EndImportDate = DateTime.Now;
            queueItem.Status = untrustedEntitiesEncountered
                ? DataSourceQueueStatuses.DataLoadCompletedPartially
                : DataSourceQueueStatuses.DataLoadCompleted;
            await _ctx.SaveChangesAsync();
        }

        public async Task<bool> CheckIfUnitExists(StatUnitTypes unitType, string statId) =>
            await _getStatUnitSet[unitType].AnyAsync(x => x.StatId == statId && !x.ParrentId.HasValue);
    }
}
