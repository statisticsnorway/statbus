using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Helpers
{
    public class StatUnitAnalysisHelper
    {
        private readonly NSCRegDbContext _ctx;

        public StatUnitAnalysisHelper(NSCRegDbContext ctx)
        {
            _ctx = ctx;
        }

        /// <summary>
        /// Getting not analyzed statistical unit filtered by user query
        /// </summary>
        /// <param name="analysisQueue">Analysis queue item</param>
        /// <returns>Statistical unit</returns>
        public StatisticalUnit GetStatisticalUnitForAnalysis(AnalysisQueue analysisQueue)
        {
            return _ctx.StatisticalUnits.Include(x => x.PersonsUnits).Include(x => x.Address).FirstOrDefault(su =>
                (_ctx.StatisticalUnitHistory.Any(c => c.StatId == su.StatId && su.StartPeriod >= c.EndPeriod && su.StartPeriod <= c.EndPeriod) &&
                 !_ctx.AnalysisLogs.Any(al =>
                     al.AnalysisQueueId == analysisQueue.Id && al.AnalyzedUnitId == su.RegId)) ||
                (su.StartPeriod >= analysisQueue.UserStartPeriod && su.StartPeriod <= analysisQueue.UserEndPeriod &&
                !_ctx.AnalysisLogs.Any(al =>
                    al.AnalysisQueueId == analysisQueue.Id && al.AnalyzedUnitId == su.RegId))
                );
        }

        /// <summary>
        /// Getting not analyzed enterprise group filtered by user query
        /// </summary>
        /// <param name="analysisQueue">Analysis queue item</param>
        /// <returns>Enterprise group</returns>
        public EnterpriseGroup GetEnterpriseGroupForAnalysis(AnalysisQueue analysisQueue)
        {
            return _ctx.EnterpriseGroups.Include(x => x.PersonsUnits).Include(x => x.Address).FirstOrDefault(su =>
                !_ctx.AnalysisLogs.Any(al =>
                    al.AnalysisQueueId == analysisQueue.Id && al.AnalyzedUnitId == su.RegId) &&
                su.StartPeriod >= analysisQueue.UserStartPeriod && su.StartPeriod <= analysisQueue.UserEndPeriod);
        }
    }
}
