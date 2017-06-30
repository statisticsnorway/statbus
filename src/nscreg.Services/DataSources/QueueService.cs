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

        public QueueService(NSCRegDbContext ctx)
        {
            _ctx = ctx;
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
            return queueItem;
        }

        public async Task ProcessRawEntity(IReadOnlyDictionary<string, string> rawEntity, DataSource dataSource)
        {
            var baseUnit = await GetBaseUnit(rawEntity, dataSource);
            StatUnitKeyValueParser.ParseAndMutateStatUnit(
                dataSource.VariablesMappingArray.ToDictionary(x => x.source, x => x.target), 
                rawEntity, 
                baseUnit);

        }

        private async Task<IStatisticalUnit> GetBaseUnit(IReadOnlyDictionary<string, string> rawEntity, DataSource dataSource)
        {
            var statIdKey = DataSourceHelpers.StatIdSourceKey(dataSource.VariablesMappingArray);
            if (rawEntity.TryGetValue(statIdKey, out string statId))
            {
                switch (dataSource.StatUnitType)
                {
                    case StatUnitTypes.LocalUnit:
                        return await _ctx.LocalUnits.FirstOrDefaultAsync(lo => lo.StatId == statId);
                    case StatUnitTypes.LegalUnit:
                        return await _ctx.LegalUnits.FirstOrDefaultAsync(le => le.StatId == statId);
                    case StatUnitTypes.EnterpriseUnit:
                        return await _ctx.LegalUnits.FirstOrDefaultAsync(eu => eu.StatId == statId);
                    case StatUnitTypes.EnterpriseGroup:
                        return await _ctx.EnterpriseGroups.FirstOrDefaultAsync(eg => eg.StatId == statId);
                    default:
                        throw new ArgumentOutOfRangeException();
                }
            }
            switch (dataSource.StatUnitType)
            {
                case StatUnitTypes.LocalUnit:
                    return new LocalUnit();
                case StatUnitTypes.LegalUnit:
                    return new LegalUnit();
                case StatUnitTypes.EnterpriseUnit:
                    return new EnterpriseUnit();
                case StatUnitTypes.EnterpriseGroup:
                    return new EnterpriseGroup();
                default:
                    throw new ArgumentOutOfRangeException();
            }
        }
    }
}
