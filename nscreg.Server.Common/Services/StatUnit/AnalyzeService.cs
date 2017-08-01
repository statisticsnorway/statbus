using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Services.Analysis.StatUnit;

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

            var analyzeErrors = _dbContext.AnalysisErrors.Where(ae => ae.AnalysisLogId == analysisLogId)
                .Include(x => x.StatisticalUnit).ToList().GroupBy(x => x.RegId)
                .Select(g => g.First());

            var records = analyzeErrors.Select(ar => new InconsistentRecord(ar.RegId, ar.StatisticalUnit.UnitType,
                ar.StatisticalUnit.Name, summaryMessages)).ToList();

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
