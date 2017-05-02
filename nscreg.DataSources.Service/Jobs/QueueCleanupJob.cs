using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using nscreg.DataSources.Service.Interfaces;

namespace nscreg.DataSources.Service.Jobs
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
