using nscreg.Data;
using nscreg.Server.Models.DataSources;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using System.Linq;
using System.Linq.Dynamic.Core;
using System;
using nscreg.Resources.Languages;
using nscreg.Server.Core;
using nscreg.Server.Models;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Services
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

            var sortBy = string.IsNullOrEmpty(query.SortBy)
                ? "Id"
                : query.SortBy;

            var orderRule = query.OrderByValue == OrderRule.Asc
                ? "ASC"
                : "DESC";

            var filtered = _context.DataSources
                .AsNoTracking()
                .Where(ds => string.IsNullOrEmpty(wildcard) || ds.Name.Contains(wildcard))
                .OrderBy($"{sortBy} {orderRule}");

            var total = await filtered.CountAsync();
            var totalPages = (int) Math.Ceiling((double) total / query.PageSize);
            var skip = query.PageSize * (Math.Min(totalPages, query.Page) - 1);

            var result = await filtered
                .Skip(skip)
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
