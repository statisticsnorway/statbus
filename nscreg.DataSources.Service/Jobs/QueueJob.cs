using System;
using System.Threading;
using Microsoft.Extensions.Configuration;
using nscreg.DataSources.Service.Interfaces;

namespace nscreg.DataSources.Service.Jobs
{
    internal class QueueJob : IJob
    {
        public int Interval { get; }

        public QueueJob(int dequeueInterval)
        {
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