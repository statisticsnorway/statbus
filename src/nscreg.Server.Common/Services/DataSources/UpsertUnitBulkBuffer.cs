using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using EFCore.BulkExtensions;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.DataSources
{
    public class UpsertUnitBulkBuffer
    {
        private bool _isEnabledFlush = true;
        private List<IStatisticalUnit> Buffer { get; }
        private readonly NSCRegDbContext _context;
        private const int MaxBulkOperationsBufferedCount = 300;

        public UpsertUnitBulkBuffer(NSCRegDbContext context, int maxCount = 100)
        {
            Buffer = new List<IStatisticalUnit>();
            _context = context;
        }

        public async Task AddToBufferAsync(IStatisticalUnit element)
        {
            Buffer.Add(element);
            if (Buffer.Count >= MaxBulkOperationsBufferedCount && _isEnabledFlush)
            {
                await Flush();
            }
            
        }

        private async Task Flush()
        {
            //TODO : Решить проблему с Edit и HistoryIds
            await _context.BulkInsertOrUpdateAsync(Buffer, new BulkConfig { TrackingEntities = false });
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
