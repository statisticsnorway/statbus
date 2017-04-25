using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Core;
using nscreg.Server.Models;
using nscreg.Server.Models.Regions;

namespace nscreg.Server.Services
{
    public class RegionsService
    {
        private readonly NSCRegDbContext _context;

        public RegionsService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
        }

        public async Task<SearchVm<Region>> RegionsPaginatedAsync(PaginationModel model, Expression<Func<Region, bool>> predicate = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            var total = await query.CountAsync();
            var regions = await query.OrderBy(v => v.Name)
                .Skip(model.PageSize * (model.Page - 1))
                .Take(model.PageSize)
                .ToListAsync();
            return SearchVm<Region>.Create(regions, total);
        }

        public async Task<List<Region>> ListAsync(Expression<Func<Region, bool>> predicate = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
             return await query.OrderBy(v => v.Name).ToListAsync();
        }

        public async Task<Region> GetAsync(int id)
        {
            var region = await _context.Regions.SingleOrDefaultAsync(x => x.Id == id);
            if (region == null) throw new BadRequestException(nameof(Resource.RegionNotExistsError));
            return region;
        }

        public async Task<Region> CreateAsync(RegionM data)
        {
            if (await _context.Regions.AnyAsync(x => x.Name == data.Name))
            {
                throw new BadRequestException(nameof(Resource.RegionAlreadyExistsError));
            }
            var region = new Region {Name = data.Name};
            _context.Add(region);
            await _context.SaveChangesAsync();
            return region;
        }

        public async Task EditAsync(int id, RegionM data)
        {
            if (await _context.Regions.AnyAsync(x => x.Id != id &&  x.Name == data.Name))
            {
                throw new BadRequestException(nameof(Resource.RegionAlreadyExistsError));
            }
            var region = await GetAsync(id);
            region.Name = data.Name;
            await _context.SaveChangesAsync();
        }

        public async Task DeleteUndelete(int id, bool delete)
        {
                var region = await GetAsync(id);
                region.IsDeleted = delete;
                await _context.SaveChangesAsync();
        }
    }
}