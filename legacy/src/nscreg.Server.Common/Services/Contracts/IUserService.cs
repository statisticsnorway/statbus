using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Common.Models.Users;

namespace nscreg.Server.Common.Services.Contracts
{
    public interface IUserService
    {
        Task<UserListVm> GetAllPagedAsync(UserListFilter filter);
        UserVm GetUserVmById(string id);
        Task<SystemFunctions[]> GetSystemFunctionsByUserId(string userId);
        Task<DataAccessPermissions> GetDataAccessAttributes(string userId, StatUnitTypes? type);
        Task SetUserStatus(string id, bool isSuspend);
        Task<bool> IsInRoleAsync(string userId, string role);
        Task<bool> IsLoginExist(string login);
        User GetUserById(string userId);
        Task RelateUserRegionsAsync(User user, IUserSubmit data);
        Task RelateUserActivityCategoriesAsync(User user, IUserSubmit data);
    }
}
