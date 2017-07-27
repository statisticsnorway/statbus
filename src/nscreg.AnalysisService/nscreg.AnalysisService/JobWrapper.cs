using System;
using System.Threading;
using nscreg.AnalysisService.Interfaces;

namespace nscreg.AnalysisService
{
    internal class JobWrapper : IJob
    {
        private readonly IJob _job;
        private readonly object _syncObject = new object();

        public int Interval => _job.Interval;
        public string Name { get; }

        public JobWrapper(IJob job)
        {
            Name = Guid.NewGuid().ToString("D");
            _job = job;
        }

        public void Execute(CancellationToken cancellationToken)
        {
            if (cancellationToken.IsCancellationRequested || !Monitor.TryEnter(_syncObject)) return;
            try
            {
                _job.Execute(cancellationToken);
            }
            catch (Exception e)
            {
                OnException(e);
            }
            finally
            {
                Monitor.Exit(_syncObject);
            }
        }

        public void OnException(Exception e)
        {
            _job.OnException(e);
        }

        public void JobContext(Action work)
        {
            lock (_syncObject)
            {
                work();
            }
        }
    }
}
