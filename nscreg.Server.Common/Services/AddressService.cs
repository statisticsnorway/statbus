using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Server.Common.Services
{
    public class AddressService :IAddressService
    {
        private readonly NSCRegDbContext _context;

        public AddressService(NSCRegDbContext context)
        {
            _context = context;
        }

        public async Task<AddressListModel> GetAsync(int page, int pageSize, Expression<Func<Address, bool>> predicate = null)
        {
            IQueryable<Address> query = _context.Address;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            var total = query.Count();
            var resultGroup = await query
                .Skip(pageSize * (page-1))
                .Take(pageSize)
                .ToListAsync();
            return new AddressListModel
            {
                TotalCount = total,
                CurrentPage = page,
                Addresses = Mapper.Map<IList<AddressModel>>(resultGroup ?? new List<Address>()),
                PageSize = pageSize,
                TotalPages = (int)Math.Ceiling((double)(total) / pageSize)
            };
        }

        public async Task<AddressModel> GetByIdAsync(int id)
        {
            return Mapper.Map<AddressModel>(await _context.Address.FirstOrDefaultAsync(x => x.Id == id));
        }

        public async Task<AddressModel> CreateAsync(AddressModel model)
        {
            var result = Mapper.Map<Address>(model);
            _context.Address.Add(result);
            await _context.SaveChangesAsync();
            return Mapper.Map<AddressModel>(result);
        }

        public async Task UpdateAsync(int id, AddressModel model)
        {
            var address = Mapper.Map<Address>(model);
            address.Id = id;
            _context.Address.Update(address);
            await _context.SaveChangesAsync();
        }

        public async Task DeleteAsync(int id)
        {
            var address = await _context.Address.FirstAsync(x => x.Id == id);
            _context.Address.Remove(address);
            await _context.SaveChangesAsync();
        }
    }
}
