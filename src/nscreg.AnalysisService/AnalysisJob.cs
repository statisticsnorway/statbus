using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;
using nscreg.ServicesUtils.Interfaces;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Analysis work class
    /// </summary>
    internal class AnalysisJob : IJob
    {
        private readonly NSCRegDbContext _ctx;
        public int Interval { get; }
        private readonly IStatUnitAnalyzeService _analysisService;
        private readonly ILogger _logger;

        public AnalysisJob(NSCRegDbContext ctx, int dequeueInterval,
            IStatUnitAnalyzeService analysisService, ILogger logger)
        {
            _ctx = ctx;
            _analysisService = analysisService;
            Interval = dequeueInterval;
            _logger = logger;
        }

        /// <summary>
        /// Analysis processing method
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.LogInformation("analysis queue attempt...");
            var analysisQueue = await _ctx.AnalysisQueues.FirstOrDefaultAsync(aq => aq.ServerEndPeriod == null, cancellationToken);
            if (analysisQueue != null)
            {
                _logger.LogInformation("analizing stat units queue {0}", analysisQueue.Id);
                await _analysisService.AnalyzeStatUnits(analysisQueue);
            }
        }

        /// <summary>
        /// Exception handler method
        /// </summary>
        public void OnException(Exception e)
        {
            _logger.LogError("queue exception {0}", e);
        }
    }
}
