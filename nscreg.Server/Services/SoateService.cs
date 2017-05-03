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
using nscreg.Server.Models.Addresses;
using nscreg.Server.Models.Soates;
using nscreg.Server.Services.Contracts;

namespace nscreg.Server.Services
{
    public class SoateService 
    {
        private readonly NSCRegDbContext _context;

        public SoateService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
        }

        public async Task<SearchVm<Soate>> ListAsync(PaginationModel model, Expression<Func<Soate, bool>> predicate = null)
        {
            IQueryable<Soate> query = _context.Soates;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            var total = await query.CountAsync();
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;
            var soates = await query.OrderBy(v => v.Code)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .ToListAsync();
            return SearchVm<Soate>.Create(soates, total);
        }

        public Task<List<Soate>> ListAsync(Expression<Func<Soate, bool>> predicate = null, int? limit = null)
        {
            IQueryable<Soate> query = _context.Soates;
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

        public async Task<Soate> GetAsync(int id)
        {
            var soate = await _context.Soates.SingleOrDefaultAsync(x => x.Id == id);
            if (soate == null) throw new BadRequestException(nameof(Resource.SoateNotExistsError));
            return soate;
        }

        public async Task<SoateM> GetAsync(string code)
        {
            var soate = await _context.Soates.FirstOrDefaultAsync(x => x.Code.TrimEnd('0').Equals(code));
            return Mapper.Map<SoateM>(soate);
        }

        public async Task<Soate> CreateAsync(SoateM data)
        {
            if (await _context.Soates.AnyAsync(x => x.Code == data.Code))
            {
                throw new BadRequestException(nameof(Resource.SoateAlreadyExistsError));
            }
            var soate = new Soate { Name = data.Name,
                Code = data.Code,
                AdminstrativeCenter = data.AdminstrativeCenter};
            _context.Add(soate);
            await _context.SaveChangesAsync();
            return soate;
        }

        public async Task EditAsync(int id, SoateM data)
        {
            if (await _context.Soates.AnyAsync(x => x.Id != id && x.Code == data.Code))
            {
                throw new BadRequestException(nameof(Resource.SoateAlreadyExistsError));
            }
            var soate = await GetAsync(id);
            soate.Name = data.Name;
            soate.Code = data.Code;
            soate.AdminstrativeCenter = data.AdminstrativeCenter;
            await _context.SaveChangesAsync();
        }

        public async Task DeleteUndelete(int id, bool delete)
        {
            var soate = await GetAsync(id);
            soate.IsDeleted = delete;
            await _context.SaveChangesAsync();
        }
    }
}
