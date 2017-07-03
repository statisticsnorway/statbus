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
        private readonly Dictionary<StatUnitTypes, Func<string, Task<IStatisticalUnit>>> _findByType;
        // TODO: use new TUnit()?
        private static readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit>> CreateByType
            = new Dictionary<StatUnitTypes, Func<IStatisticalUnit>>
            {
                [StatUnitTypes.LocalUnit] = () => new LocalUnit(),
                [StatUnitTypes.LegalUnit] = () => new LegalUnit(),
                [StatUnitTypes.EnterpriseUnit] = () => new EnterpriseUnit(),
                [StatUnitTypes.EnterpriseGroup] = () => new EnterpriseGroup(),
            };

        private static Func<string, Task<IStatisticalUnit>> GetFindByStatIdForConcreteStatUnits(
            IQueryable<IStatisticalUnit> concreteStatUnits)
            => statId
                => concreteStatUnits.SingleOrDefaultAsync(x => x.StatId == statId);

        public QueueService(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            // TODO: use _ctx.Set<TUnit>?
            _findByType = new Dictionary<StatUnitTypes, Func<string, Task<IStatisticalUnit>>>
            {
                [StatUnitTypes.LocalUnit] = GetFindByStatIdForConcreteStatUnits(_ctx.LocalUnits),
                [StatUnitTypes.LegalUnit] = GetFindByStatIdForConcreteStatUnits(_ctx.LegalUnits),
                [StatUnitTypes.EnterpriseUnit] = GetFindByStatIdForConcreteStatUnits(_ctx.EnterpriseUnits),
                [StatUnitTypes.EnterpriseGroup] = GetFindByStatIdForConcreteStatUnits(_ctx.EnterpriseGroups),
            };
        }

        public async Task<DataSourceQueue> Dequeue()
        {
            var queueItem = _ctx.DataSourceQueues
                .Include(item => item.DataSource)
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
                => raw.TryGetValue(GetStatIdSourceKey(mapping), out string statId)
                    ? await _findByType[unitType](statId)
                    : CreateByType[unitType]();
        }

        public async Task LogStatUnitUpload(
            DataSourceQueue queueItem,
            IStatisticalUnit unit,
            DateTime started,
            DateTime ended,
            DataUploadingLogStatuses status,
            string note)
        {
            _ctx.DataSourceQueues.Attach(queueItem);
            queueItem.DataUploadingLogs.Add(new DataUploadingLog
            {
                TargetStatId = unit.StatId,
                StatUnitName = unit.Name,
                SerializedUnit = SerializeToString(unit),
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
    }
}
