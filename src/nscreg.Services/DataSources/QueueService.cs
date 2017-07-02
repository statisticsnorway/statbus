using System;
using System.Collections.Generic;
using nscreg.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.DataSources;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Services.DataSources
{
    public class QueueService
    {
        private readonly NSCRegDbContext _ctx;
        private readonly Dictionary<StatUnitTypes, Func<string, Task<IStatisticalUnit>>> _findByType;
        private static readonly Dictionary<StatUnitTypes, Func<IStatisticalUnit>> _createByType
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
            Func<IQueryable<IStatisticalUnit>, Func<string, Task<IStatisticalUnit>>> getFindByStatIdForConcreteStatUnits =
                concreteStatUnits =>
                    statId =>
                        concreteStatUnits.SingleOrDefaultAsync(x => x.StatId == statId);
            _findByType = new Dictionary<StatUnitTypes, Func<string, Task<IStatisticalUnit>>>
            {
                [StatUnitTypes.LocalUnit] = getFindByStatIdForConcreteStatUnits(_ctx.LocalUnits),
                [StatUnitTypes.LegalUnit] = getFindByStatIdForConcreteStatUnits(_ctx.LegalUnits),
                [StatUnitTypes.EnterpriseUnit] = getFindByStatIdForConcreteStatUnits(_ctx.EnterpriseUnits),
                [StatUnitTypes.EnterpriseGroup] = getFindByStatIdForConcreteStatUnits(_ctx.EnterpriseGroups),
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
            var resultUnit = await GetStatUnitBase();

            StatUnitKeyValueParser.ParseAndMutateStatUnit(
                propMapping.ToDictionary(x => x.source, x => x.target), 
                raw,
                resultUnit);

            return resultUnit;

            async Task<IStatisticalUnit> GetStatUnitBase()
                => raw.TryGetValue(DataSourceHelpers.StatIdSourceKey(propMapping), out string statId)
                    ? await _findByType[unitType](statId)
                    : _createByType[unitType]();
        }

        public async Task FinishQueueItem(DataSourceQueue queueItem, bool untrustedEntitiesEncountered)
        {
            queueItem.Status = untrustedEntitiesEncountered
                ? DataSourceQueueStatuses.DataLoadCompletedPartially
                : DataSourceQueueStatuses.DataLoadCompleted;
            _ctx.DataSourceQueues.Attach(queueItem);
            await _ctx.SaveChangesAsync();
        }
    }
}
