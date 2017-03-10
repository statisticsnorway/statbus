using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Server.Services
{
    public class RegionsService
    {
        private readonly NSCRegDbContext _context;

        public RegionsService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
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

        public async Task AddAsync(Region region)
        {
            _context.Add(region);
            await _context.SaveChangesAsync();
        }
    }
}
