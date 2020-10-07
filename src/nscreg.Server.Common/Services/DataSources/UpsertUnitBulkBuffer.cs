using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using EFCore.BulkExtensions;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    ///TODO продумать логику и создавать разные коллекции сущностей и разные bulkInsert
    public class UpsertUnitBulkBuffer
    {
        private bool _isEnabledFlush = true;
        private List<StatisticalUnit> Buffer { get; }
        private readonly NSCRegDbContext _context;
        private const int MaxBulkOperationsBufferedCount = 1000;

        public UpsertUnitBulkBuffer(NSCRegDbContext context)
        {
            Buffer = new List<StatisticalUnit>();
            _context = context;
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

            var addresses = Buffer.SelectMany(x => new[] { x.Address, x.ActualAddress, x.PostalAddress }).Where(x => x != null).ToList();
            var activityUnits = Buffer.SelectMany(x => x.ActivitiesUnits).ToList();
            var activities = activityUnits.Select(z => z.Activity).ToList();
            var personUnits = Buffer.SelectMany(x => x.PersonsUnits).ToList();
            var persons = personUnits.Select(z => z.Person).ToList();
            var enterpriseGroups = Buffer.SelectMany(x => x.PersonsUnits.Select(z => z.EnterpriseGroup)).ToList();
            
            await _context.BulkInsertOrUpdateAsync(activities, bulkConfig);
            await _context.BulkInsertOrUpdateAsync(enterpriseGroups, bulkConfig);
            await _context.BulkInsertOrUpdateAsync(persons, bulkConfig);
            await _context.BulkInsertOrUpdateAsync(addresses, bulkConfig);

            foreach (var unit in Buffer)
            {
                unit.AddressId = unit.Address?.Id;
                unit.ActualAddressId = unit.ActualAddress?.Id;
                unit.PostalAddressId = unit.PostalAddress?.Id;
            }
            var enterprises = Buffer.OfType<EnterpriseUnit>().ToList();
            await _context.BulkInsertOrUpdateAsync(enterprises, bulkConfig);

            var legals = Buffer.OfType<LegalUnit>().ToList();
            legals.ForEach(x => x.EnterpriseUnitRegId = x.EnterpriseUnit.RegId);
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
