using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Models.Soates;
using nscreg.Server.Services.Contracts;

namespace nscreg.Server.Services
{
    public class SoateService : ISoateService
    {
        private readonly NSCRegDbContext _context;

        public SoateService(NSCRegDbContext context)
        {
            _context = context;
        }
        public async Task<IList<SoateModel>> GetAsync(Expression<Func<Soate, bool>> predicate = null, int limit = 5)
        {
            IQueryable<Soate> query = _context.Soates;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            query = query.Take(limit);
            return Mapper.Map<IList<SoateModel>>(await query.ToListAsync());
        }

        public async Task<SoateModel> GetByCode(string soateCode)
        {
            var soate = await _context.Soates.FirstOrDefaultAsync(x => x.Code.TrimEnd('0').Equals(soateCode));
            return Mapper.Map<SoateModel>(soate);
        }
    }
}
