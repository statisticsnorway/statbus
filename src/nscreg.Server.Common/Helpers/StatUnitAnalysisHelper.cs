using System;
using System.Linq;
using System.Threading.Tasks;
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
        public async Task<StatisticalUnit> GetStatisticalUnitForAnalysis(AnalysisQueue analysisQueue)
        {
            return await _ctx.StatisticalUnits
                .Include(x => x.PersonsUnits)
                .Include(x => x.Address)
                .FirstOrDefaultAsync(su => !su.IsDeleted && 
                                      (_ctx.StatisticalUnitHistory
                                           .Any(c => c.StatId == su.StatId && c.EndPeriod >= analysisQueue.UserStartPeriod && c.EndPeriod <= analysisQueue.UserEndPeriod) ||
                                       su.StartPeriod >= analysisQueue.UserStartPeriod) &&
                                      !_ctx.AnalysisLogs
                                          .Any(al =>
                                              al.AnalysisQueueId == analysisQueue.Id && al.AnalyzedUnitId == su.RegId)
                );
        }

        /// <summary>
        /// Getting not analyzed enterprise group filtered by user query
        /// </summary>
        /// <param name="analysisQueue">Analysis queue item</param>
        /// <returns>Enterprise group</returns>
        public async Task<EnterpriseGroup> GetEnterpriseGroupForAnalysis(AnalysisQueue analysisQueue)
        {
            return await _ctx.EnterpriseGroups
                .Include(x => x.PersonsUnits)
                .Include(x => x.Address)
                .FirstOrDefaultAsync(su => !su.IsDeleted &&
                    (_ctx.EnterpriseGroupHistory
                         .Any(c => c.StatId == su.StatId && c.EndPeriod >= analysisQueue.UserStartPeriod && c.EndPeriod <= analysisQueue.UserEndPeriod) ||
                     su.StartPeriod >= analysisQueue.UserStartPeriod) &&
                !_ctx.AnalysisLogs
                    .Any(al =>
                        al.AnalysisQueueId == analysisQueue.Id && al.AnalyzedUnitId == su.RegId)
            );
        }
    }
}
