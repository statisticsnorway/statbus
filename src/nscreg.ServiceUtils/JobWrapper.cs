using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using nscreg.ServicesUtils.Interfaces;

namespace nscreg.ServicesUtils
{
    internal class JobWrapper : IJob
    {
        private readonly IJob _job;
        private readonly ILogger _logger;
        private readonly object _syncObject = new object();

        public int Interval => _job.Interval;
        public string Name { get; }

        public JobWrapper(IJob job, ILogger logger)
        {
            Name = Guid.NewGuid().ToString("D");
            _job = job;
            _logger = logger;
        }

        public Task Execute(CancellationToken cancellationToken)
        {
            Console.WriteLine($"pre-execute {Thread.CurrentThread.ManagedThreadId}");
            if (cancellationToken.IsCancellationRequested || !Monitor.TryEnter(_syncObject)) return Task.CompletedTask;
            try
            {
                Console.WriteLine($"executing {Thread.CurrentThread.ManagedThreadId}");
                _job.Execute(cancellationToken).Wait(cancellationToken);
            }
            catch (Exception e)
            {
                OnException(e);
            }
            finally
            {
                Monitor.Exit(_syncObject);
            }
            return Task.CompletedTask;
        }

        public void OnException(Exception e)
        {
            try
            {
               // _job.OnException(e);
            }
            catch (Exception exception)
            {
                _logger.LogError(Name, exception);
            }
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
