using System;
using System.Threading;
using nscreg.Data;
using nscreg.DataUploadService.Interfaces;

namespace nscreg.DataUploadService.Jobs
{
    internal class QueueJob : IJob
    {
        public int Interval { get; }
        private readonly NSCRegDbContext _ctx;

        public QueueJob(NSCRegDbContext ctx, int dequeueInterval)
        {
            _ctx = ctx;
            Interval = dequeueInterval;
        }

        public void Execute(CancellationToken cancellationToken)
        {
            //TODO: Dequeue Batch and update status in single transaction
            Thread.Sleep(10000);
            // Process each of works and set result status
            throw new NotImplementedException();
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
