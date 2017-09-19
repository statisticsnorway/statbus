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

        public async Task<DataSourceEditVm> GetById(int id) =>
            DataSourceEditVm.Create(await _context.DataSources.FindAsync(id));

        public async Task<DataSourceVm> Create(SubmitM data)
        {
            var entity = data.CreateEntity();
            if (await _context.DataSources.AnyAsync(ds => ds.Name == entity.Name))
                throw new BadRequestException(nameof(Resource.DataSourceNameExists));
            _context.DataSources.Add(entity);
            await _context.SaveChangesAsync();
            return DataSourceVm.Create(entity);
        }

        public async Task Edit(int id, SubmitM data)
        {
            var existing = await _context.DataSources.FindAsync(id);
            if (existing == null)
                throw new BadRequestException(nameof(Resource.DataSourceNotFound));
            data.UpdateEntity(existing);
            await _context.SaveChangesAsync();
        }

        public async Task Delete(int id)
        {
            var entity = await _context.DataSources.FindAsync(id);
            if (entity == null)
                throw new BadRequestException(nameof(Resource.DataSourceNotFound));
            if (await _context.DataSourceQueues.AnyAsync(item => item.DataSourceId == id))
                throw new BadRequestException(nameof(Resource.DataSourceHasQueuedItems));
            _context.DataSources.Remove(entity);
            await _context.SaveChangesAsync();
        }
    }
}
