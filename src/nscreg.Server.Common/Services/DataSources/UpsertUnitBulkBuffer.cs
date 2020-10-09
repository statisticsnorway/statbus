using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using EFCore.BulkExtensions;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    public class UpsertUnitBulkBuffer
    {
        private bool _isEnabledFlush = true;
        private List<StatisticalUnit> Buffer { get; }
        private readonly NSCRegDbContext _context;
        public ElasticService ElasticService { get; }
        private const int MaxBulkOperationsBufferedCount = 1000;

        public UpsertUnitBulkBuffer(NSCRegDbContext context, ElasticService elasticService)
        {
            Buffer = new List<StatisticalUnit>();
            _context = context;
            ElasticService = elasticService;
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

            var addresses = Buffer.SelectMany(x => new[] { x.Address, x.ActualAddress, x.PostalAddress }).Where(x => x != null).Distinct().ToList();
            var activityUnits = Buffer.SelectMany(x => x.ActivitiesUnits).ToList();
            var activities = activityUnits.Select(z => z.Activity).Distinct().ToList();

            var personUnits = Buffer.SelectMany(x => x.PersonsUnits).ToList();
            var persons = personUnits.Select(z => z.Person).Distinct().ToList();

            var foreignCountry = Buffer.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList();
            
            await _context.BulkInsertOrUpdateAsync(activities, bulkConfig);
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
                z.UnitId = x.RegId;
            }));
            Buffer.ForEach(x => x.ForeignParticipationCountriesUnits.ForEach(z => z.UnitId = x.RegId));

            await _context.BulkInsertOrUpdateAsync(activityUnits);
            await _context.BulkInsertOrUpdateAsync(personUnits);
            await _context.BulkInsertOrUpdateAsync(foreignCountry);

            Buffer.Clear();
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
}
