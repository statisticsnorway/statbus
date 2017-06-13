using System;
using nscreg.Data;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Services.DataSources
{
    public class QueueService
    {
        private readonly NSCRegDbContext _ctx;

        public QueueService(NSCRegDbContext ctx)
        {
            _ctx = ctx;
        }

        public async Task<DataSourceQueue> Dequeue()
        {
            var queueItem = _ctx.DataSourceQueues.FirstOrDefault(item => item.Status == DataSourceQueueStatuses.InQueue);
            if (queueItem == null) return null;
            queueItem.StartImportDate = DateTime.Now;
            queueItem.Status = DataSourceQueueStatuses.Loading;
            await _ctx.SaveChangesAsync();
            return queueItem;
        }
    }
}
