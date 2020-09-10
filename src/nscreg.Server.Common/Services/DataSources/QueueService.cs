using System;
using System.Collections.Generic;
using nscreg.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
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

        public async Task<(StatisticalUnit, string)> GetStatUnitFromRawEntity(
            IReadOnlyDictionary<string, object> raw,
            StatUnitTypes unitType,
            (string source, string target)[] propMapping,
            DataSourceUploadTypes uploadType,
            DataSourceAllowedOperation allowedOperation)
        {
            var mapping = propMapping
                .GroupBy(x => x.source)
                .ToDictionary(x => x.Key, x => x.Select(y => y.target).ToArray());

            var resultUnit = await GetStatUnitBase(allowedOperation);

            raw = await TransformReferenceField(raw, mapping, "Persons.Person.Role", (value) =>
                {
                    return _ctx.PersonTypes.FirstOrDefaultAsync(x =>
                        x.Name == value || x.NameLanguage1 == value || x.NameLanguage2 == value);
                });

            ParseAndMutateStatUnit(mapping, raw, resultUnit);

            var errors = await _postProcessor.FillIncompleteDataOfStatUnit(resultUnit, uploadType);

            return (resultUnit, errors);

            async Task<StatisticalUnit> GetStatUnitBase(DataSourceAllowedOperation operation)
            {
                StatisticalUnit existing = null;

                var key = GetStatIdSourceKey(propMapping);
                if (key.HasValue() && raw.TryGetValue(key, out var statId))
                    existing = await _getStatUnitSet[unitType]
                        .SingleOrDefaultAsync(x => x.StatId == statId.ToString() && operation != DataSourceAllowedOperation.Create);
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
                logEntry.SerializedUnit = JsonConvert.SerializeObject(unit, new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver() });
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

        private async Task<IReadOnlyDictionary<string, object>> TransformReferenceField<TEntity>(IReadOnlyDictionary<string, object> raw, Dictionary<string, string[]> mappings, string referenceField, Func<string, Task<TEntity>> getEntityAction)
            where TEntity : LookupBase 
        {
            Dictionary<string,object> result = new Dictionary<string, object>();

            var hasKey = mappings.Values.SelectMany(x => x).Any(x=> x == referenceField);

            if (!hasKey) return raw;

            var parts = referenceField.Split('.');
            bool isContainsKey = raw.ContainsKey(parts.FirstOrDefault());
            if (isContainsKey && raw[parts.FirstOrDefault()] is IList<KeyValuePair<string, Dictionary<string, string>>> parents)
            {
                List<int> idsArray = new List<int>();
                List<string> errorArray = new List<string>();
                foreach (var par in parents)
                {
                    var value = par.Value[parts.Last()];
                    var entity = await getEntityAction(value);
                    if (entity != null)
                    {
                        idsArray.Add(entity.Id);
                    }
                    else
                    {
                        errorArray.Add(value);
                    }
                }
                if (errorArray.Any()) throw new Exception($"Reference for {string.Join(",",errorArray)} was not found");
                foreach (var keyValuePair in raw)
                {
                    if (keyValuePair.Value is string)
                    {
                        result[keyValuePair.Key] = keyValuePair.Value;
                    }
                    else {
                        var val = keyValuePair.Value as IList<KeyValuePair<string, Dictionary<string, string>>>;
                        for (int i = 0; i < val.Count; i++)
                        {
                            var elem = new List<KeyValuePair<string, Dictionary<string, string>>>();
                            foreach (var kv in keyValuePair.Value as IList<KeyValuePair<string, Dictionary<string, string>>>)
                            {
                                var dic = new Dictionary<string,string>();
                                foreach (var kvValue in kv.Value)
                                {
                                    dic.Add(kvValue.Key, kvValue.Key == parts.Last() ? idsArray[i].ToString() : kvValue.Value);
                                }
                                elem.Add(new KeyValuePair<string, Dictionary<string, string>>(kv.Key, dic));
                            }

                            result[keyValuePair.Key] = elem;
                        }
                    }
                }
                return result;
            }

            return raw;
        }
    }
}
