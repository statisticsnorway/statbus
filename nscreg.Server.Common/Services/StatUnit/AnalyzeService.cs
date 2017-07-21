using System.Linq;
using System.Threading.Tasks;
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

        public async Task<SearchVm<InconsistentRecord>> GetInconsistentRecordsAsync(PaginationModel model)
        {
            var validator = new InconsistentRecordValidator();

            var units = _dbContext.StatisticalUnits
                .Where(x => !x.IsDeleted && x.ParentId == null)
                .Select(x => validator.Specify(x))
                .Where(x => x.Inconsistents.Count > 0);

            var groups = _dbContext.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParentId == null)
                .Select(x => validator.Specify(x))
                .Where(x => x.Inconsistents.Count > 0);

            var records = units.Union(groups);
            var total = await records.CountAsync();
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;

            var paginatedRecords = await records.OrderBy(v => v.Type).ThenBy(v => v.Name)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .ToListAsync();

            return SearchVm<InconsistentRecord>.Create(paginatedRecords, total);
        }
    }
}
