using System.Collections.Generic;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class AnalyzeService
    {
        private readonly NSCRegDbContext _dbContext;

        public AnalyzeService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public SearchVm<InconsistentRecord> GetInconsistentRecords(PaginationModel model, int analysisLogId)
        {
            var summaryMessages = _dbContext.AnalysisLogs.FirstOrDefault(al => al.Id == analysisLogId).SummaryMessages;

            var analyzeGroupErrors = _dbContext.AnalysisGroupErrors.Where(ae => ae.AnalysisLogId == analysisLogId)
                .Include(x => x.EnterpriseGroup).ToList().GroupBy(x => x.GroupRegId)
                .Select(g => g.First()).ToList();

            var analyzeStatisticalErrors = _dbContext.AnalysisStatisticalErrors.Where(ae => ae.AnalysisLogId == analysisLogId)
                .Include(x => x.StatisticalUnit).ToList().GroupBy(x => x.StatisticalRegId)
                .Select(g => g.First());

            var records = new List<InconsistentRecord>();

            records.AddRange(analyzeGroupErrors.Select(error => new InconsistentRecord(error.GroupRegId,
                error.EnterpriseGroup.UnitType, error.EnterpriseGroup.Name, summaryMessages)));
            records.AddRange(analyzeStatisticalErrors.Select(error => new InconsistentRecord(error.StatisticalRegId,
                error.StatisticalUnit.UnitType, error.StatisticalUnit.Name, summaryMessages)));

            var total = records.Count;
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;

            var paginatedRecords = records.OrderBy(v => v.Type).ThenBy(v => v.Name)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .ToList();

            return SearchVm<InconsistentRecord>.Create(paginatedRecords, total);
        }
    }
}
