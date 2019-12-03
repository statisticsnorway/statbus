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
using nscreg.Utilities;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Class service address
    /// </summary>
    public class AddressService : IAddressService
    {
        private readonly NSCRegDbContext _context;

        public AddressService(NSCRegDbContext context)
        {
            _context = context;
        }

        /// <summary>
        /// Method returning a list of all addresses
        /// </summary>
        /// <param name = "page"> Page </param>
        /// <param name = "pageSize"> Page size </param>
        /// <param name = "predicate"> Predicate </param>
        /// <returns> </returns>
        public async Task<AddressListModel> GetAsync(
            int page,
            int pageSize,
            Expression<Func<Address, bool>> predicate = null)
        {
            IQueryable<Address> query = _context.Address.Include(x => x.Region);
            if (predicate != null) query = query.Where(predicate);
            var total = await query.CountAsync();
            var resultGroup = await query
                .Skip(Pagination.CalculateSkip(pageSize, page, total))
                .Take(pageSize)
                .ToListAsync();
            return new AddressListModel
            {
                TotalCount = total,
                CurrentPage = page,
                Addresses = Mapper.Map<IList<AddressModel>>(resultGroup ?? new List<Address>()),
                PageSize = pageSize,
                TotalPages = (int) Math.Ceiling((double) total / pageSize)
            };
        }

        /// <summary>
        /// Method returning a specific address
        /// </summary>
        /// <param name = "id"> Id addresses </param>
        /// <returns> </returns>
        public async Task<AddressModel> GetByIdAsync(int id)
            => Mapper.Map<AddressModel>(
                await _context.Address.Include(x => x.Region).FirstOrDefaultAsync(x => x.Id == id));

        /// <summary>
        /// Method for creating an address
        /// </summary>
        /// <param name = "model"> Model </param>
        /// <returns> </returns>
        public async Task<AddressModel> CreateAsync(AddressModel model)
        {
            var result = Mapper.Map<Address>(model);
            _context.Address.Add(result);
            await _context.SaveChangesAsync();
            return Mapper.Map<AddressModel>(result);
        }

        /// <summary>
        /// Address change method
        /// </summary>
        /// <param name = "id"> Id addresses </param>
        /// <param name = "model"> Model </param>
        /// <returns> </returns>
        public async Task UpdateAsync(int id, AddressModel model)
        {
            var address = Mapper.Map<Address>(model);
            address.Id = id;
            _context.Address.Update(address);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Address removal method
        /// </summary>
        /// <param name = "id"> Id addresses </param>
        /// <returns> </returns>
        public async Task DeleteAsync(int id)
        {
            var address = await _context.Address.FirstAsync(x => x.Id == id);
            _context.Address.Remove(address);
            await _context.SaveChangesAsync();
        }
    }
}
