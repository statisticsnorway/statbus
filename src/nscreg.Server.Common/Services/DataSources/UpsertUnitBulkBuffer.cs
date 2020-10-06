using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using EFCore.BulkExtensions;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.DataSources
{
    ///TODO продумать логику и создавать разные коллекции сущностей и разные bulkInsert
    public class UpsertUnitBulkBuffer
    {
        private bool _isEnabledFlush = true;
        private List<LegalUnit> Buffer { get; }
        private readonly NSCRegDbContext _context;
        private const int MaxBulkOperationsBufferedCount = 300;
        private readonly BulkConfig _config;

        public UpsertUnitBulkBuffer(NSCRegDbContext context)
        {
            _config = new BulkConfig() { PreserveInsertOrder = true, SetOutputIdentity = true };
            Buffer = new List<LegalUnit>();
            _context = context;
        }

        public async Task AddToBufferAsync(LegalUnit element)
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
            //BulkInsert не срабатывает по Discriminator в базу ложаться юниты с Discriminator "StatisticalUnit"

            var addresses = Buffer.SelectMany(x => new List<Address>{x.Address, x.ActualAddress, x.PostalAddress}).Where(x => x != null).ToList(); // проблема  при присвоении юниту, не будет понятно какой адресс куда относится
            await _context.BulkInsertAsync(addresses, _config);

            await _context.BulkInsertOrUpdateAsync(Buffer, _config);
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
