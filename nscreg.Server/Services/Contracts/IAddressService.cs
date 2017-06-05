using System;
using System.Linq.Expressions;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Models.Addresses;

namespace nscreg.Server.Services.Contracts
{
    public interface IAddressService
    {
        Task<AddressListModel> GetAsync(int page, int pageSize, Expression<Func<Address, bool>> predicate = null);
        Task<AddressModel> GetByIdAsync(int id);
        Task<AddressModel> CreateAsync(AddressModel model);
        Task UpdateAsync(int id, AddressModel model);
        Task DeleteAsync(int id);
    }
}
