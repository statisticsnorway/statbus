using System;
using System.Collections.Generic;
using nscreg.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
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

        public QueueService(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            _getStatUnitSet = new Dictionary<StatUnitTypes, IQueryable<StatisticalUnit>>
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

        public async Task<StatisticalUnit> GetStatUnitFromRawEntity(
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

            await FillIncompleteDataOfStatUnit(resultUnit);

            return resultUnit;

            async Task<StatisticalUnit> GetStatUnitBase()
            {
                StatisticalUnit existing = null;
                {
                    var key = GetStatIdSourceKey(mapping);
                    if (!string.IsNullOrEmpty(key) && raw.TryGetValue(key, out var statId))
                        existing = await _getStatUnitSet[unitType]
                            .SingleOrDefaultAsync(x => x.StatId == statId && !x.ParentId.HasValue);
                }

                if (existing == null) return CreateByType[unitType]();

                _ctx.Entry(existing).State = EntityState.Detached;
                return existing;
            }

            async Task FillIncompleteDataOfStatUnit(StatisticalUnit unit)
            {
                if (unit.Activities?.Any(activity => activity.Id == 0) == true)
                    await unit.ActivitiesUnits
                        .ForEachAsync(async au =>
                        {
                            if (au.Activity.Id == 0)
                                au.Activity = await GetFilledActivity(au.Activity);
                        });

                if (unit.Address?.Id == 0)
                    unit.Address = await GetFilledAddress(unit.Address);

                if (unit.ForeignParticipationCountry?.Id == 0)
                    unit.ForeignParticipationCountry = await GetFilledCountry(unit.ForeignParticipationCountry);

                if (unit.LegalForm?.Id == 0)
                    unit.LegalForm = await GetFilledLegalForm(unit.LegalForm);

                if (unit.Persons?.Any(person => person.Id == 0) == true)
                    await unit.PersonsUnits.ForEachAsync(async pu =>
                    {
                        if (pu.Person.Id == 0)
                            pu.Person = await GetFilledPerson(pu.Person);
                    });

                if (unit.InstSectorCode?.Id == 0)
                    unit.InstSectorCode = await GetFilledSectorCode(unit.InstSectorCode);
            }

            async Task<Activity> GetFilledActivity(Activity sample) =>
                await _ctx.Activities
                    .Include(a => a.ActivityRevxCategory)
                    .FirstOrDefaultAsync(a =>
                        a.ActivityRevxCategory != null
                        && !a.ActivityRevxCategory.IsDeleted
                        && (sample.ActivityType == 0 || a.ActivityType == sample.ActivityType)
                        && (sample.ActivityRevx == 0 || a.ActivityRevx == sample.ActivityRevx)
                        && (sample.ActivityRevy == 0 || a.ActivityRevy == sample.ActivityRevy)
                        && (string.IsNullOrWhiteSpace(sample.ActivityRevxCategory.Code) ||
                            a.ActivityRevxCategory.Code == sample.ActivityRevxCategory.Code)
                        && (string.IsNullOrWhiteSpace(sample.ActivityRevxCategory.Name) ||
                            a.ActivityRevxCategory.Name == sample.ActivityRevxCategory.Name)
                        && (string.IsNullOrWhiteSpace(sample.ActivityRevxCategory.Section) ||
                            a.ActivityRevxCategory.Section == sample.ActivityRevxCategory.Section))
                ?? sample;

            async Task<Address> GetFilledAddress(Address sample) =>
                await _ctx.Address
                    .Include(a => a.Region)
                    .FirstOrDefaultAsync(a =>
                        a.Region != null
                        && !a.Region.IsDeleted
                        && (string.IsNullOrWhiteSpace(sample.AddressPart1) || a.AddressPart1 == sample.AddressPart1)
                        && (string.IsNullOrWhiteSpace(sample.AddressPart2) || a.AddressPart2 == sample.AddressPart2)
                        && (string.IsNullOrWhiteSpace(sample.AddressPart3) || a.AddressPart3 == sample.AddressPart3)
                        && (string.IsNullOrWhiteSpace(sample.GpsCoordinates) ||
                            a.GpsCoordinates == sample.GpsCoordinates)
                        && (string.IsNullOrWhiteSpace(sample.Region.Name) || a.Region.Name == sample.Region.Name)
                        && (string.IsNullOrWhiteSpace(sample.Region.Code) || a.Region.Code == sample.Region.Code)
                        && (string.IsNullOrWhiteSpace(sample.Region.AdminstrativeCenter) ||
                            a.Region.AdminstrativeCenter == sample.Region.AdminstrativeCenter))
                ?? sample;

            async Task<Country> GetFilledCountry(Country sample) =>
                await _ctx.Countries.FirstOrDefaultAsync(c =>
                    !c.IsDeleted
                    && (string.IsNullOrWhiteSpace(sample.Code) || c.Code == sample.Code)
                    && (string.IsNullOrWhiteSpace(sample.Name) || c.Name == sample.Name))
                ?? sample;

            async Task<LegalForm> GetFilledLegalForm(LegalForm sample) =>
                await _ctx.LegalForms.FirstOrDefaultAsync(lf =>
                    !lf.IsDeleted
                    && (string.IsNullOrWhiteSpace(sample.Code) || lf.Code == sample.Code)
                    && (string.IsNullOrWhiteSpace(sample.Name) || lf.Name == sample.Name))
                ?? sample;

            async Task<Person> GetFilledPerson(Person sample) =>
                await _ctx.Persons
                    .Include(p => p.NationalityCode)
                    .FirstOrDefaultAsync(p =>
                        (string.IsNullOrWhiteSpace(sample.GivenName) || p.GivenName == sample.GivenName)
                        && (string.IsNullOrWhiteSpace(sample.Surname) || p.Surname == sample.Surname)
                        && (string.IsNullOrWhiteSpace(sample.PersonalId) || p.PersonalId == sample.PersonalId)
                        && (!sample.BirthDate.HasValue || p.BirthDate == sample.BirthDate))
                ?? sample;

            async Task<SectorCode> GetFilledSectorCode(SectorCode sample) =>
                await _ctx.SectorCodes.FirstOrDefaultAsync(sc =>
                    !sc.IsDeleted
                    && (string.IsNullOrWhiteSpace(sample.Code) || sc.Code == sample.Code)
                    && (string.IsNullOrWhiteSpace(sample.Name) || sc.Name == sample.Name))
                ?? sample;
        }

        public async Task LogStatUnitUpload(
            DataSourceQueue queueItem,
            StatisticalUnit unit,
            IEnumerable<string> props,
            DateTime? started,
            DateTime? ended,
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
            await _getStatUnitSet[unitType].AnyAsync(x => x.StatId == statId && !x.ParentId.HasValue);

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
    }
}
