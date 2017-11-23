using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Common.Models.Users;

namespace nscreg.Server.Common.Services.Contracts
{
    public interface IUserService
    {
        UserListVm GetAllPaged(UserListFilter filter);
        UserVm GetById(string id);
        Task<SystemFunctions[]> GetSystemFunctionsByUserId(string userId);
        Task<DataAccessPermissions> GetDataAccessAttributes(string userId, StatUnitTypes? type);
        Task SetUserStatus(string id, bool isSuspend);
        Task<bool> IsInRoleAsync(string userId, string role);
    }
}
