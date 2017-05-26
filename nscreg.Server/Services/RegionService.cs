using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Core;
using nscreg.Server.Models;
using nscreg.Server.Models.Regions;

namespace nscreg.Server.Services
{
    public class RegionService 
    {
        private readonly NSCRegDbContext _context;

        public RegionService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
        }

        public async Task<SearchVm<Region>> ListAsync(PaginationModel model, Expression<Func<Region, bool>> predicate = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            var total = await query.CountAsync();
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;
            var regions = await query.OrderBy(v => v.Code)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .ToListAsync();
            return SearchVm<Region>.Create(regions, total);
        }

        public Task<List<Region>> ListAsync(Expression<Func<Region, bool>> predicate = null, int? limit = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }

            if (limit.HasValue)
            {
                query = query.Take(limit.Value);
            }

            return query.Where(v => !v.IsDeleted).OrderBy(v => v.Code).ToListAsync();
        }

        public async Task<Region> GetAsync(int id)
        {
            var region = await _context.Regions.SingleOrDefaultAsync(x => x.Id == id);
            if (region == null) throw new BadRequestException(nameof(Resource.RegionNotExistsError));
            return region;
        }

        public async Task<RegionM> GetAsync(string code)
        {
            var region = await _context.Regions.FirstOrDefaultAsync(x => x.Code.TrimEnd('0').Equals(code));
            return Mapper.Map<RegionM>(region);
        }

        public async Task<Region> CreateAsync(RegionM data)
        {
            if (await _context.Regions.AnyAsync(x => x.Code == data.Code))
            {
                throw new BadRequestException(nameof(Resource.RegionAlreadyExistsError));
            }
            var region = new Region { Name = data.Name,
                Code = data.Code,
                AdminstrativeCenter = data.AdminstrativeCenter};
            _context.Add(region);
            await _context.SaveChangesAsync();
            return region;
        }

        public async Task EditAsync(int id, RegionM data)
        {
            if (await _context.Regions.AnyAsync(x => x.Id != id && x.Code == data.Code))
            {
                throw new BadRequestException(nameof(Resource.RegionAlreadyExistsError));
            }
            var region = await GetAsync(id);
            region.Name = data.Name;
            region.Code = data.Code;
            region.AdminstrativeCenter = data.AdminstrativeCenter;
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
