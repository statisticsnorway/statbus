using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Server.Models;
using nscreg.Server.Models.DataSourceQueues;
using nscreg.Utilities.Enums;
using System.Linq.Dynamic.Core;


namespace nscreg.Server.Services
{
    public class DataSourceQueuesService
    {
        private NSCRegDbContext dbContext;
        public DataSourceQueuesService(NSCRegDbContext ctx)
        {
            dbContext = ctx;
        }

        public async Task<SearchVm<DataSourceQueueVm>> GetAllDataSourceQueues(SearchQueryM query)
        {

            var sortBy = string.IsNullOrEmpty(query.SortBy)
                ? "Id"
                : query.SortBy;

            var orderRule = query.OrderByValue == OrderRule.Asc
                ? "ASC"
                : "DESC";

            var filtered = dbContext.DataSourceQueues
                .Include(x => x.DataSource)
                .Include( x => x.User)
                .AsNoTracking();

            if (query.Status.HasValue)
                filtered = filtered.Where(x => x.Status == query.Status.Value);

            if (query.DateFrom.HasValue && query.DateTo.HasValue)
            {
                filtered = filtered.Where(x => x.StartImportDate >= query.DateFrom.Value && x.StartImportDate <= query.DateTo.Value);
            }
            else
            {
                if (query.DateFrom.HasValue)
                    filtered = filtered.Where(x => x.StartImportDate >= query.DateFrom.Value);

                if (query.DateTo.HasValue)
                    filtered = filtered.Where(x => x.StartImportDate <= query.DateTo.Value);
            }
               

            filtered = filtered.OrderBy($"{sortBy} {orderRule}");

            var total = await filtered.CountAsync();
            var totalPages = (int)Math.Ceiling((double)total / query.PageSize);
            var skip = query.PageSize * (Math.Abs(Math.Min(totalPages, query.Page) - 1));

            var result = await filtered
                .Skip(skip)
                .Take(query.PageSize)
                .ToListAsync();


            return SearchVm<DataSourceQueueVm>.Create(result.Select(DataSourceQueueVm.Create), total);

        }
    }
}
