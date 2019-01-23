using System;
using System.Collections.Generic;
using nscreg.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Utilities.Extensions;
using Nest;
using Newtonsoft.Json;
using ServiceStack;
using static nscreg.Business.DataSources.StatUnitKeyValueParser;

namespace nscreg.Server.Common.Services.DataSources
{
    public class QueueService
    {
        private readonly NSCRegDbContext _ctx;

        private readonly Dictionary<StatUnitTypes, IQueryable<StatisticalUnit>> _getStatUnitSet;

        private static readonly Dictionary<StatUnitTypes, Func<StatisticalUnit>> CreateByType
            = new Dictionary<StatUnitTypes, Func<StatisticalUnit>>
            {
                [StatUnitTypes.LocalUnit] = () => new LocalUnit(),
                [StatUnitTypes.LegalUnit] = () => new LegalUnit(),
                [StatUnitTypes.EnterpriseUnit] = () => new EnterpriseUnit(),
            };

        private readonly StatUnitPostProcessor _postProcessor;

        public QueueService(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            _getStatUnitSet = new Dictionary<StatUnitTypes, IQueryable<StatisticalUnit>>
            {
                [StatUnitTypes.LocalUnit] = _ctx.LocalUnits
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region)
                    .Include(x => x.PersonsUnits)
                    .ThenInclude(x=>x.Person)
                    .Include(x=>x.ActivitiesUnits)
                    .ThenInclude(x=>x.Activity)
                    .Include(x=>x.ForeignParticipationCountriesUnits)
                    .ThenInclude(x=>x.Country)
                    .AsNoTracking(),
                [StatUnitTypes.LegalUnit] = _ctx.LegalUnits
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region)
                    .Include(x => x.PersonsUnits)
                    .ThenInclude(x => x.Person)
                    .Include(x => x.ActivitiesUnits)
                    .ThenInclude(x => x.Activity)
                    .Include(x => x.ForeignParticipationCountriesUnits)
                    .ThenInclude(x => x.Country)
                    .AsNoTracking(),
                [StatUnitTypes.EnterpriseUnit] = _ctx.EnterpriseUnits
                    .Include(x => x.Address)
                    .ThenInclude(x => x.Region)
                    .Include(x => x.PersonsUnits)
                    .ThenInclude(x => x.Person)
                    .Include(x => x.ActivitiesUnits)
                    .ThenInclude(x => x.Activity)
                    .Include(x => x.ForeignParticipationCountriesUnits)
                    .ThenInclude(x => x.Country)
                    .AsNoTracking(),
            };
            _postProcessor = new StatUnitPostProcessor(ctx);
        }

        public async Task<DataSourceQueue> Dequeue()
        {
            var queueItem = await _ctx.DataSourceQueues
                .Include(item => item.DataSource)
                .Include(item => item.DataUploadingLogs)
                .FirstOrDefaultAsync(item => item.Status == DataSourceQueueStatuses.InQueue);

            if (queueItem == null) return null;

            queueItem.StartImportDate = DateTime.Now;
            queueItem.Status = DataSourceQueueStatuses.Loading;
            await _ctx.SaveChangesAsync();

            _ctx.Entry(queueItem).State = EntityState.Detached;
            return queueItem;
        }

        public async Task<StatisticalUnit> GetStatUnitFromRawEntity(
            IReadOnlyDictionary<string, string> raw,
            StatUnitTypes unitType,
            IEnumerable<(string source, string target)> propMapping,
            DataSourceUploadTypes uploadType)
        {
            var rawMapping = propMapping as (string source, string target)[] ?? propMapping.ToArray();
            var mapping = rawMapping
                .GroupBy(x => x.source)
                .ToDictionary(x => x.Key, x => x.Select(y => y.target).ToArray());

            var resultUnit = await GetStatUnitBase();

            raw = await TransformReferenceFiled(raw, mapping, "Persons.Role", (value) =>
                {
                    return _ctx.PersonTypes.FirstOrDefaultAsync(x =>
                        x.Name == value || x.NameLanguage1 == value || x.NameLanguage2 == value);
                });

            ParseAndMutateStatUnit(mapping, raw, resultUnit);

            await _postProcessor.FillIncompleteDataOfStatUnit(resultUnit, uploadType);

            return resultUnit;

            async Task<StatisticalUnit> GetStatUnitBase()
            {
                StatisticalUnit existing = null;

                var key = GetStatIdSourceKey(rawMapping);
                if (key.HasValue() && raw.TryGetValue(key, out var statId))
                    existing = await _getStatUnitSet[unitType]
                        .SingleOrDefaultAsync(x => x.StatId == statId);
                else if (uploadType == DataSourceUploadTypes.Activities)
                    throw new InvalidOperationException("Missing statId required for activity upload");
                  

                if (existing == null) return CreateByType[unitType]();

                _ctx.Entry(existing).State = EntityState.Detached;
                return existing;
            }

        }

        public async Task LogUnitUpload(
            DataSourceQueue queueItem,
            string rawUnit,
            DateTime? started,
            StatisticalUnit unit,
            DateTime? ended,
            DataUploadingLogStatuses status,
            string note,
            IReadOnlyDictionary<string, string[]> messages,
            IEnumerable<string> summaryMessages)
        {
            _ctx.DataSourceQueues.Attach(queueItem);
            if (queueItem.DataUploadingLogs == null)
                queueItem.DataUploadingLogs = new List<DataUploadingLog>();
            var logEntry = new DataUploadingLog
            {
                StartImportDate = started,
                EndImportDate = ended,
                SerializedRawUnit = rawUnit,
                Status = status,
                Note = note,
                Errors = JsonConvert.SerializeObject(messages ?? new Dictionary<string, string[]>()),
                Summary = JsonConvert.SerializeObject(summaryMessages ?? Array.Empty<string>()),
            };
            if (unit != null)
            {
                logEntry.TargetStatId = unit.StatId;
                logEntry.StatUnitName = unit.Name;
                logEntry.SerializedUnit = JsonConvert.SerializeObject(unit);
            }
            queueItem.DataUploadingLogs.Add(logEntry);
            await _ctx.SaveChangesAsync();
            _ctx.Entry(queueItem).State = EntityState.Detached;
        }

        public async Task FinishQueueItem(DataSourceQueue queueItem, DataSourceQueueStatuses status, string note = null)
        {
            _ctx.DataSourceQueues.Attach(queueItem);
            queueItem.EndImportDate = DateTime.Now;
            queueItem.Status = status;
            queueItem.Note = note;
            await _ctx.SaveChangesAsync();
        }

        public async Task<bool> CheckIfUnitExists(StatUnitTypes unitType, string statId) =>
            await _getStatUnitSet[unitType].AnyAsync(x => x.StatId == statId);

        public async Task ResetDequeuedByTimeout(int timeoutMilliseconds)
        {
            var moment = DateTime.Now.AddMilliseconds(-timeoutMilliseconds);
            var hanged = (await _ctx.DataSourceQueues
                    .Where(x => x.Status == DataSourceQueueStatuses.Loading)
                    .ToListAsync())
                .Where(x => x.StartImportDate < moment)
                .ToList();
            if (!hanged.Any()) return;
            hanged.ForEach(x =>
            {
                x.Status = DataSourceQueueStatuses.InQueue;
                x.StartImportDate = null;
            });
            await _ctx.SaveChangesAsync();
        }

        private async Task<IReadOnlyDictionary<string, string>> TransformReferenceFiled<TEntity>(IReadOnlyDictionary<string, string> raw, Dictionary<string, string[]> mappings, string referenceField, Func<string, Task<TEntity>> getEntityAction)
            where TEntity : LookupBase 
        {
            Dictionary<string,string> result = new Dictionary<string, string>();

            string key = string.Empty;
            foreach (var mapping in mappings)
            {
                if (mapping.Value.Any(x => x == referenceField))
                {
                    key = mapping.Key;
                }
            }

            if (!key.IsNullOrEmpty())
            {
                var value = raw[key];
                var entity = await getEntityAction(value);
                int id;
                if (entity != null)
                {
                    id = entity.Id;
                }
                else
                {
                    throw new Exception($"Reference for {value} was not found");
                }
                foreach (var keyValuePair in raw)
                {
                    var newValue = keyValuePair.Key == key ? id.ToString() : keyValuePair.Value;
                    result[keyValuePair.Key] = newValue;
                }
                return result;
            }

            return raw;
        }
    }
}
