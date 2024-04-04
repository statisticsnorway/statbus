using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using NLog;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Services
{
    /// <summary>
    /// Analysis work class
    /// </summary>
    public class AnalyseWorker
    {
        private readonly NSCRegDbContext _ctx;
        private readonly IStatUnitAnalyzeService _analysisService;
        private static readonly Logger _logger = LogManager.GetCurrentClassLogger();

        public AnalyseWorker(NSCRegDbContext ctx,
            IStatUnitAnalyzeService analysisService)
        {
            _ctx = ctx;
            _analysisService = analysisService;
        }

        /// <summary>
        /// Analysis processing method
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute()
        {
            _logger.Info("analysis queue attempt...");
            var analysisQueue = await _ctx.AnalysisQueues.FirstOrDefaultAsync(aq => aq.ServerEndPeriod == null);
            if (analysisQueue != null)
            {
                _logger.Info("analizing stat units queue {0}", analysisQueue.Id);
                await _analysisService.AnalyzeStatUnits(analysisQueue);
            }
        }
    }
}
