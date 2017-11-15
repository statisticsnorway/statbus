using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Microsoft.Extensions.Logging;
using nscreg.ServicesUtils.Interfaces;
using PeterKottas.DotNetCore.WindowsService.Base;
using PeterKottas.DotNetCore.WindowsService.Interfaces;

namespace nscreg.ServicesUtils
{
    public class JobService : MicroService, IMicroService
    {
        private readonly List<JobWrapper> _jobs;
        private readonly CancellationTokenSource _tokenSource = new CancellationTokenSource();

        public JobService(ILogger logger, params IJob[] jobs)
        {
            _jobs = jobs.Select(v => new JobWrapper(v, logger)).ToList();
        }

        public void Start()
        {
            StartBase();
            foreach (var job in _jobs)
            {
                Timers.Start(
                    job.Name,
                    job.Interval,
                    () => job.Execute(_tokenSource.Token).Wait(),
                    job.OnException
                );
            }
        }

        public void Stop()
        {
            _tokenSource.Cancel();
            foreach (var job in _jobs)
            {
                job.JobContext(() => Timers.Stop(job.Name));
            }
            StopBase();
        }
    }
}
