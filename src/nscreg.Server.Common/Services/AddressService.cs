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
   /// Класс сервис адреса
   /// </summary>
    public class AddressService : IAddressService
    {
        private readonly NSCRegDbContext _context;

        public AddressService(NSCRegDbContext context)
        {
            _context = context;
        }

        /// <summary>
        /// Метод возвращающий список всех адесов
        /// </summary>
        /// <param name="page">Страница</param>
        /// <param name="pageSize">Размер страницы</param>
        /// <param name="predicate">Предикат</param>
        /// <returns></returns>
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
        /// Метод возвращающий определённый адрес
        /// </summary>
        /// <param name="id">Id адреса</param>
        /// <returns></returns>
        public async Task<AddressModel> GetByIdAsync(int id)
            => Mapper.Map<AddressModel>(
                await _context.Address.Include(x => x.Region).FirstOrDefaultAsync(x => x.Id == id));

        /// <summary>
        /// Метод создания адреса
        /// </summary>
        /// <param name="model">Модель</param>
        /// <returns></returns>
        public async Task<AddressModel> CreateAsync(AddressModel model)
        {
            var result = Mapper.Map<Address>(model);
            _context.Address.Add(result);
            await _context.SaveChangesAsync();
            return Mapper.Map<AddressModel>(result);
        }

        /// <summary>
        /// Метод изменения адреса
        /// </summary>
        /// <param name="id">Id адреса</param>
        /// <param name="model">Модель</param>
        /// <returns></returns>
        public async Task UpdateAsync(int id, AddressModel model)
        {
            var address = Mapper.Map<Address>(model);
            address.Id = id;
            _context.Address.Update(address);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Метод удаления адреса
        /// </summary>
        /// <param name="id">Id адреса</param>
        /// <returns></returns>
        public async Task DeleteAsync(int id)
        {
            var address = await _context.Address.FirstAsync(x => x.Id == id);
            _context.Address.Remove(address);
            await _context.SaveChangesAsync();
        }
    }
}
