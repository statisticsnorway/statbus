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
                await FlushLegalUnitsAsync();
            }
            
        }

        public async Task FlushLegalUnitsAsync()
        {
            //TODO : Решить проблему с Edit и HistoryIds
            var addresses = Buffer.SelectMany(x => new[] { x.Address, x.ActualAddress, x.PostalAddress }).Where(x => x != null).ToList();
            await _context.BulkInsertOrUpdateAsync(addresses, new BulkConfig { SetOutputIdentity = true, PreserveInsertOrder = true });
            foreach (var unit in Buffer)
            {
                unit.AddressId = unit.Address?.Id;
                unit.ActualAddressId = unit.ActualAddress?.Id;
                unit.PostalAddressId = unit.PostalAddress?.Id;
            }
            //todo остальные связанные сущности


            var enterprises = Buffer.OfType<EnterpriseUnit>().ToList();
            await _context.BulkInsertOrUpdateAsync(enterprises, new BulkConfig { SetOutputIdentity = true, PreserveInsertOrder = true });

            var legals = Buffer.OfType<LegalUnit>().ToList();
            legals.ForEach(x => x.EnterpriseUnitRegId = x.EnterpriseUnit.RegId);
            await _context.BulkInsertOrUpdateAsync(legals, new BulkConfig { SetOutputIdentity = true, PreserveInsertOrder = true });

            var locals = Buffer.OfType<LocalUnit>().ToList();
            locals.ForEach(x => x.LegalUnitId = x.LegalUnit?.RegId);
            await _context.BulkInsertOrUpdateAsync(locals, new BulkConfig { SetOutputIdentity = true, PreserveInsertOrder = true });

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
