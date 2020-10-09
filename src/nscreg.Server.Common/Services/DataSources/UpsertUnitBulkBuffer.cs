using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using EFCore.BulkExtensions;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Data.Entities.History;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    public class UpsertUnitBulkBuffer
    {
        private bool _isEnabledFlush = true;
        private List<StatisticalUnit> Buffer { get; }
        private List<EnterpriseUnit> BufferToDelete { get; }
        private List<IStatisticalUnitHistory> HistoryBuffer { get; }
        private readonly NSCRegDbContext _context;
        public ElasticService ElasticSearchService { get; }
        private const int MaxBulkOperationsBufferedCount = 1000;

        public UpsertUnitBulkBuffer(NSCRegDbContext context, ElasticService elasticSearchService)
        {
            HistoryBuffer = new List<IStatisticalUnitHistory>();
            BufferToDelete = new List<EnterpriseUnit>();
            Buffer = new List<StatisticalUnit>();
            _context = context;
            ElasticSearchService = elasticSearchService;
        }

        public void AddToDeleteBufferAsync(EnterpriseUnit unit)
        {
            BufferToDelete.Add(unit);
        }

        public void AddToHistoryBufferAsync(IStatisticalUnitHistory unitHistory)
        {
            HistoryBuffer.Add(unitHistory);

        }
        public async Task AddToBufferAsync(StatisticalUnit element)
        {
            Buffer.Add(element);
            if (Buffer.Count >= MaxBulkOperationsBufferedCount && _isEnabledFlush)
            {
                await FlushAsync();
            }
        }

        public async Task FlushAsync()
        {
            //TODO : Решить проблему с Edit и HistoryIds
            var bulkConfig = new BulkConfig {SetOutputIdentity = true, PreserveInsertOrder = true};

            var addresses = Buffer.SelectMany(x => new[] { x.Address, x.ActualAddress, x.PostalAddress }).Where(x => x != null).Distinct(new IdComparer<Address>()).ToList();
            var activityUnits = Buffer.SelectMany(x => x.ActivitiesUnits).ToList();
            var activities = activityUnits.Select(z => z.Activity).Distinct(new IdComparer<Activity>()).ToList();

            var personUnits = Buffer.SelectMany(x => x.PersonsUnits).ToList();
            var persons = personUnits.Select(z => z.Person).Distinct(new IdComparer<Person>()).ToList();

            var foreignCountry = Buffer.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList();
            
            await _context.BulkInsertOrUpdateAsync(activities, bulkConfig);

            var activitiesNew = activities.Where(x => x.Id == 0).ToList();
            
            await _context.BulkInsertOrUpdateAsync(persons, bulkConfig);
            await _context.BulkInsertOrUpdateAsync(addresses, bulkConfig);

            Buffer.ForEach(unit =>
            {
                unit.AddressId = unit.Address?.Id;
                unit.ActualAddressId = unit.ActualAddress?.Id;
                unit.PostalAddressId = unit.PostalAddress?.Id;
            });
            var enterprises = Buffer.OfType<EnterpriseUnit>().ToList();

            var groups = enterprises.Select(x => x.EnterpriseGroup).Where(z => z != null).ToList();
            await _context.BulkInsertOrUpdateAsync(groups, bulkConfig);
            
            enterprises.ForEach(x => x.EntGroupId = x.EnterpriseGroup?.RegId);
            await _context.BulkInsertOrUpdateAsync(enterprises, bulkConfig);

            var legals = Buffer.OfType<LegalUnit>().ToList();
            legals.ForEach(x => x.EnterpriseUnitRegId = x.EnterpriseUnit?.RegId);
            await _context.BulkInsertOrUpdateAsync(legals, bulkConfig);

            var locals = Buffer.OfType<LocalUnit>().ToList();
            locals.ForEach(x => x.LegalUnitId = x.LegalUnit?.RegId);
            await _context.BulkInsertOrUpdateAsync(locals, bulkConfig);

            Buffer.ForEach(x => x.ActivitiesUnits.ForEach(z =>
            {
                z.ActivityId = z.Activity.Id;
                z.Unit = x;
                z.UnitId = x.RegId;
            }));

            var activitiesNull = activityUnits.Where(x => x.ActivityId == 0).ToList();
            Buffer.ForEach(x => x.ForeignParticipationCountriesUnits.ForEach(z => z.UnitId = x.RegId));

            await _context.BulkInsertOrUpdateAsync(activityUnits);
            await _context.BulkInsertOrUpdateAsync(personUnits);
            await _context.BulkInsertOrUpdateAsync(foreignCountry);
            await _context.BulkDeleteAsync(BufferToDelete);

            var hLocalUnits = HistoryBuffer.OfType<LocalUnitHistory>().ToList();
            var hLegalUnits = HistoryBuffer.OfType<LegalUnitHistory>().ToList();
            var hEnterpriseUnits = HistoryBuffer.OfType<EnterpriseUnit>().ToList();

            await _context.BulkInsertOrUpdateAsync(hLocalUnits);
            await _context.BulkInsertOrUpdateAsync(hLegalUnits);
            await _context.BulkInsertOrUpdateAsync(hEnterpriseUnits);
            if (Buffer.Any())
            {
                var entities = Buffer.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>)
                    .Concat(groups.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>)).ToList();
                await ElasticSearchService.UpsertDocumentList(entities);
            }
                
            Buffer.Clear();
            BufferToDelete.Clear();
            HistoryBuffer.Clear();
        }
        public void DisableFlushing()
        {
            _isEnabledFlush = false;
        }
        public void EnableFlushing()
        {
            _isEnabledFlush = true;
        }
    }

    public class IdComparer<T>: IEqualityComparer<T> where T: IModelWithId
    {
        public bool Equals(T x, T y)
        {
            if (x == null && y == null)
                return true;

            if (x == null || y == null)
                return false;
            if (ReferenceEquals(x, y))
                return true;
            return x.Id != 0 && x.Id == y.Id;
        }

        public int GetHashCode(T obj)
        {
           return obj.Id.GetHashCode();
        }
    }
}
