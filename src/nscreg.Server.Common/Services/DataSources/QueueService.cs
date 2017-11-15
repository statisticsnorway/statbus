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

            async Task<Activity> GetFilledActivity(Activity parsedActivity) =>
                await _ctx.Activities
                    .Include(a => a.ActivityCategory)
                    .FirstOrDefaultAsync(a =>
                        a.ActivityCategory != null
                        && !a.ActivityCategory.IsDeleted
                        && (parsedActivity.ActivityType == 0 || a.ActivityType == parsedActivity.ActivityType)
                        && (parsedActivity.ActivityCategoryId == 0 || a.ActivityCategoryId == parsedActivity.ActivityCategoryId)
                        && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Code) ||
                            a.ActivityCategory.Code == parsedActivity.ActivityCategory.Code)
                        && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Name) ||
                            a.ActivityCategory.Name == parsedActivity.ActivityCategory.Name)
                        && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Section) ||
                            a.ActivityCategory.Section == parsedActivity.ActivityCategory.Section))
                ?? parsedActivity;

            async Task<Address> GetFilledAddress(Address parsedAddress) =>
                await _ctx.Address
                    .Include(a => a.Region)
                    .FirstOrDefaultAsync(a =>
                        a.Region != null
                        && !a.Region.IsDeleted
                        && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart1) ||
                            a.AddressPart1 == parsedAddress.AddressPart1)
                        && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart2) ||
                            a.AddressPart2 == parsedAddress.AddressPart2)
                        && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart3) ||
                            a.AddressPart3 == parsedAddress.AddressPart3)
                        && (string.IsNullOrWhiteSpace(parsedAddress.GpsCoordinates) ||
                            a.GpsCoordinates == parsedAddress.GpsCoordinates)
                        && (string.IsNullOrWhiteSpace(parsedAddress.Region.Name) ||
                            a.Region.Name == parsedAddress.Region.Name)
                        && (string.IsNullOrWhiteSpace(parsedAddress.Region.Code) ||
                            a.Region.Code == parsedAddress.Region.Code)
                        && (string.IsNullOrWhiteSpace(parsedAddress.Region.AdminstrativeCenter) ||
                            a.Region.AdminstrativeCenter == parsedAddress.Region.AdminstrativeCenter))
                ?? parsedAddress;

            async Task<Country> GetFilledCountry(Country parsedCountry) =>
                await _ctx.Countries.FirstOrDefaultAsync(c =>
                    !c.IsDeleted
                    && (string.IsNullOrWhiteSpace(parsedCountry.Code) || c.Code == parsedCountry.Code)
                    && (string.IsNullOrWhiteSpace(parsedCountry.Name) || c.Name == parsedCountry.Name))
                ?? parsedCountry;

            async Task<LegalForm> GetFilledLegalForm(LegalForm parsedLegalForm) =>
                await _ctx.LegalForms.FirstOrDefaultAsync(lf =>
                    !lf.IsDeleted
                    && (string.IsNullOrWhiteSpace(parsedLegalForm.Code) || lf.Code == parsedLegalForm.Code)
                    && (string.IsNullOrWhiteSpace(parsedLegalForm.Name) || lf.Name == parsedLegalForm.Name))
                ?? parsedLegalForm;

            async Task<Person> GetFilledPerson(Person parsedPerson) =>
                await _ctx.Persons
                    .Include(p => p.NationalityCode)
                    .FirstOrDefaultAsync(p =>
                        (string.IsNullOrWhiteSpace(parsedPerson.GivenName) || p.GivenName == parsedPerson.GivenName)
                        && (string.IsNullOrWhiteSpace(parsedPerson.Surname) || p.Surname == parsedPerson.Surname)
                        && (string.IsNullOrWhiteSpace(parsedPerson.PersonalId) ||
                            p.PersonalId == parsedPerson.PersonalId)
                        && (!parsedPerson.BirthDate.HasValue || p.BirthDate == parsedPerson.BirthDate))
                ?? parsedPerson;

            async Task<SectorCode> GetFilledSectorCode(SectorCode parsedSectorCode) =>
                await _ctx.SectorCodes.FirstOrDefaultAsync(sc =>
                    !sc.IsDeleted
                    && (string.IsNullOrWhiteSpace(parsedSectorCode.Code) || sc.Code == parsedSectorCode.Code)
                    && (string.IsNullOrWhiteSpace(parsedSectorCode.Name) || sc.Name == parsedSectorCode.Name))
                ?? parsedSectorCode;
        }

        public async Task LogStatUnitUpload(
            DataSourceQueue queueItem,
            StatisticalUnit unit,
            IEnumerable<string> props,
            DateTime? started,
            DateTime? ended,
            DataUploadingLogStatuses status,
            string note,
            Dictionary<string, string[]> messages = null,
            IEnumerable<string> summaryMessages = null)
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
                Errors = JsonConvert.SerializeObject(messages ?? new Dictionary<string, string[]>()),
                Summary = JsonConvert.SerializeObject(summaryMessages ?? Array.Empty<string>()),
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
