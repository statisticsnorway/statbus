using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using System.Linq.Dynamic.Core;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services
{
    public class DataSourcesService
    {
        private readonly NSCRegDbContext _context;

        public DataSourcesService(NSCRegDbContext context)
        {
            _context = context;
        }

        public async Task<SearchVm<DataSourceVm>> GetAllDataSources(SearchQueryM query)
        {
            var wildcard = query.Wildcard;
            var statUnitType = query.StatUnitType;
            var priority = (DataSourcePriority) query.Priority;
            var allowedOperations = (DataSourceAllowedOperation) query.AllowedOperations;

            var sortBy = string.IsNullOrEmpty(query.SortBy)
                ? "Id"
                : query.SortBy;

            var orderRule = query.OrderByValue == OrderRule.Asc
                ? "ASC"
                : "DESC";

            var filtered = _context.DataSources
                .AsNoTracking()
                .Where(ds => string.IsNullOrEmpty(wildcard) || ds.Name.Contains(wildcard))
                .Where(ds => statUnitType == 0 || ds.StatUnitType == (StatUnitTypes) statUnitType)
                .Where(ds => priority == 0 || ds.Priority == priority)
                .Where(ds => allowedOperations == 0 || ds.AllowedOperations == allowedOperations)
                .OrderBy($"{sortBy} {orderRule}");

            var total = await filtered.CountAsync();
            var take = query.PageSize;
            var skip = query.PageSize * (query.Page - 1);

            var result = await filtered
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(query.PageSize)
                .ToListAsync();

            return SearchVm<DataSourceVm>.Create(result.Select(DataSourceVm.Create), total);
        }

        public async Task<DataSourceVm> Create(CreateM data)
        {
            var entity = data.GetEntity();
            if (await _context.DataSources.AnyAsync(ds => ds.Name == entity.Name))
                throw new BadRequestException(nameof(Resource.DataSourceNameExists));
            _context.DataSources.Add(entity);
            await _context.SaveChangesAsync();
            return DataSourceVm.Create(entity);
        }
    }
}
