using System;
using System.Threading;
using nscreg.DataUploadService.Interfaces;

namespace nscreg.DataUploadService.Jobs
{
    public class QueueCleanupJob : IJob
    {
        public int Interval { get; } = 300000;

        public void Execute(CancellationToken cancellationToken)
        {
            //TODO: Reset processing status of each task that not running
            throw new NotImplementedException();
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
