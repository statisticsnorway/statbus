using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System.Collections.Generic;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.ActivityCategories;
using nscreg.Server.Common.Models.Roles;
using nscreg.Utilities;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис роли
    /// </summary>
    public class RoleService
    {
        private readonly NSCRegDbContext _context;

        public RoleService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
        }

        /// <summary>
        /// Метод получения списка всех ролей
        /// </summary>
        /// <param name="model">Модель поиска</param>
        /// <param name="onlyActive">Флаг активности</param>
        /// <returns></returns>
        public RoleListVm GetAllPaged(PaginatedQueryM model, bool onlyActive)
        {
            var listRoles = onlyActive
                ? _context.Roles.Where(x => x.Status == RoleStatuses.Active)
                : _context.Roles;
            var total = listRoles.Count();
            var roles = listRoles
                .Skip(Pagination.CalculateSkip(model.PageSize, model.Page, total))
                .Take(model.PageSize)
                .OrderBy(x => x.Name)
                .ToList();

            var rolesIds = roles.Select(v => v.Id).ToList();

            var usersCount =
            (from u in _context.Users
                join ur in _context.UserRoles on u.Id equals ur.UserId
                join r in _context.Roles on ur.RoleId equals r.Id
                where rolesIds.Contains(r.Id) && u.Status == UserStatuses.Active
                group r by r.Id
                into g
                select new {RoleId = g.Key, Count = g.Count()}).ToDictionary(v => v.RoleId, v => v.Count);

            foreach (var role in roles)
            {
                usersCount.TryGetValue(role.Id, out var value);
                role.ActiveUsers = value;
            }

            return RoleListVm.Create(roles.Select(RoleVm.Create), total,
                (int) Math.Ceiling((double) total / model.PageSize));
        }

        /// <summary>
        /// Метод получения роли
        /// </summary>
        /// <param name="id">Id</param>
        /// <returns></returns>
        public RoleVm GetRoleVmById(string id)
        {
            var role = GetRoleById(id);
            return RoleVm.Create(role);
        }

        public Role GetRoleById(string id)
        {
            var role = _context.Roles.Find(id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));
            return role;
        }

        /// <summary>
        /// Метод создания роли
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        public RoleVm Create(RoleSubmitM data)
        {
            if (_context.Roles.Any(r => r.Name == data.Name))
                throw new Exception(nameof(Resource.NameError));

            var role = new Role
            {
                Name = data.Name,
                Description = data.Description,
                AccessToSystemFunctionsArray = data.AccessToSystemFunctions,
                StandardDataAccessArray = data.StandardDataAccess.ToPermissionsModel(),
                NormalizedName = data.Name.ToUpper(),
                Status = RoleStatuses.Active,
                SqlWalletUser = data.SqlWalletUser
            };

            _context.Roles.Add(role);
            _context.SaveChanges();

            return RoleVm.Create(role);
        }

        /// <summary>
        /// Метод редактирования роли
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="data">Данные</param>
        public void Edit(string id, RoleSubmitM data)
        {
            var role = _context.Roles.Find(id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            if (role.Name != data.Name
                && _context.Roles.Any(r => r.Name == data.Name))
                throw new Exception(nameof(Resource.NameError));

            role.Name = data.Name;
            role.AccessToSystemFunctionsArray = data.AccessToSystemFunctions;
            role.StandardDataAccessArray = data.StandardDataAccess.ToPermissionsModel();
            role.Description = data.Description;
            role.SqlWalletUser = data.SqlWalletUser;
            _context.SaveChanges();
        }

        /// <summary>
        /// Метод переключения статуса роли
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="status">Статус роли</param>
        /// <returns></returns>
        public async Task ToggleSuspend(string id, RoleStatuses status)
        {
            var role = await _context.Roles.Include(x => x.Users).FirstOrDefaultAsync(r => r.Id == id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            var userIds = role.Users.Select(ur => ur.UserId).ToArray();

            if (status == RoleStatuses.Suspended && role.Name == DefaultRoleNames.Administrator)
                throw new Exception(nameof(Resource.DeleteSysAdminRoleError));

            if (status == RoleStatuses.Suspended && userIds.Any() &&
                await _context.Users.AnyAsync(u => userIds.Contains(u.Id) && u.Status == UserStatuses.Active))
                throw new Exception(nameof(Resource.DeleteRoleError));

            role.Status = status;
            if (status == RoleStatuses.Suspended)
            {
                var records = await _context.UserRoles.Where(x => x.RoleId == id).ToListAsync();
                _context.UserRoles.RemoveRange(records);
            }
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Метод получения активности дерева ролей
        /// </summary>
        /// <param name="parentId"></param>
        /// <returns></returns>
        public Task<List<ActivityCategoryVm>> FetchActivityTreeAsync(int parentId) => _context.ActivityCategories
            .Where(x => x.ParentId == parentId)
            .OrderBy(x => x.Code)
            .Select(x => new ActivityCategoryVm
            {
                Id = x.Id,
                Name = x.Name,
                NameLanguage1 = x.NameLanguage1,
                NameLanguage2 = x.NameLanguage2,
                Code = x.Code,
                Section = x.Section,
                ParentId = x.ParentId
            }).ToListAsync();
    }
}
