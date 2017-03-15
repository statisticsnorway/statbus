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

        public Task<List<Region>> ListAsync(Expression<Func<Region, bool>> predicate = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            return query.OrderBy(v => v.Name).ToListAsync();
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

        public async Task Delete(int id)
        {
            try
            {
                var region = await GetAsync(id);
                _context.Regions.Remove(region);
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateException e)
            {
                throw new BadRequestException(nameof(Resource.RegionDeleteError), e);
            }
        }
    }
}