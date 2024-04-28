using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using System.Linq.Dynamic.Core;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Utilities;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Data source service
    /// </summary>
    public class DataSourcesService
    {
        private readonly NSCRegDbContext _context;

        public DataSourcesService(NSCRegDbContext context)
        {
            _context = context;
        }

        /// <summary>
        /// Method for obtaining all data sources
        /// </summary>
        /// <param name = "query"> Request </param>
        /// <returns> </returns>
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
                .Where(ds => string.IsNullOrEmpty(wildcard) || ds.Name.ToLower().Contains(wildcard.ToLower()))
                .Where(ds => statUnitType == 0 || ds.StatUnitType == (StatUnitTypes) statUnitType)
                .Where(ds => priority == 0 || ds.Priority == priority)
                .Where(ds => allowedOperations == 0 || ds.AllowedOperations == allowedOperations)
                .OrderBy($"{sortBy} {orderRule}");

            
            var total = await filtered.CountAsync();

            if (query.GetAll)
            {
                var res = await filtered.ToListAsync();
                return SearchVm<DataSourceVm>.Create(res.Select(DataSourceVm.Create), total);
            }

            var result = await filtered
                .Skip(Pagination.CalculateSkip(query.PageSize, query.Page, total))
                .Take(query.PageSize)
                .ToListAsync();

            return SearchVm<DataSourceVm>.Create(result.Select(DataSourceVm.Create), total);
        }

        /// <summary>
        /// Method of obtaining a data source
        /// </summary>
        /// <param name = "id"> Id </param>
        /// <returns> </returns>
        public async Task<DataSourceEditVm> GetById(int id)
        {
            var data = await _context.DataSources.FindAsync(id);
            if (data == null)
                throw new BadRequestException(nameof(Resource.DataSourceNotFound));
            return DataSourceEditVm.Create(data);
        }

        /// <summary>
        /// Method for creating a data source
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <returns> </returns>
        public async Task<DataSourceVm> Create(SubmitM data, string userId)
        {
            var entity = data.CreateEntity(userId);
            if (await _context.DataSources.AnyAsync(ds => ds.Name == entity.Name))
                throw new BadRequestException(nameof(Resource.DataSourceNameExists));
            _context.DataSources.Add(entity);
            await _context.SaveChangesAsync();
            return DataSourceVm.Create(entity);
        }

        /// <summary>
        /// Data source editing method
        /// </summary>
        /// <param name = "id"> Id </param>
        /// <param name = "data"> Data </param>
        /// <returns> </returns>
        public async Task Edit(int id, SubmitM data, string userId)
        {
            var existing = await _context.DataSources.FindAsync(id);
            if (existing == null)
                throw new BadRequestException(nameof(Resource.DataSourceNotFound));
            data.UpdateEntity(existing, userId);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Method for deleting a data source
        /// </summary>
        /// <param name = "id"> Id </param>
        /// <returns> </returns>
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
