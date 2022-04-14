using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using NLog;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Analysis work class
    /// </summary>
    internal class AnalysisJob
    {
        private readonly NSCRegDbContext _ctx;
        public int Interval { get; }
        private readonly IStatUnitAnalyzeService _analysisService;
        private static Logger _logger = LogManager.GetCurrentClassLogger();

        public AnalysisJob(NSCRegDbContext ctx, int dequeueInterval,
            IStatUnitAnalyzeService analysisService)
        {
            _ctx = ctx;
            _analysisService = analysisService;
            Interval = dequeueInterval;
        }

        /// <summary>
        /// Analysis processing method
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.Info("analysis queue attempt...");
            var analysisQueue = await _ctx.AnalysisQueues.FirstOrDefaultAsync(aq => aq.ServerEndPeriod == null, cancellationToken);
            if (analysisQueue != null)
            {
                _logger.Info("analizing stat units queue {0}", analysisQueue.Id);
                await _analysisService.AnalyzeStatUnits(analysisQueue);
            }
        }
    }
}
