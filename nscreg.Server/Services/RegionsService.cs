using System.Collections.Generic;
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

        public async Task<List<Region>> ListAsync()
        {
            return await _context.Regions.ToListAsync();
        }

        public async Task AddAsync(Region region)
        {
            _context.Add(region);
            await _context.SaveChangesAsync();
        }
    }
}
