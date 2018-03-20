using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Regions;
using nscreg.Server.Common.Models.Users;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис пользователя
    /// </summary>
    public class UserService : IUserService
    {
        private readonly NSCRegDbContext _context;

        public UserService(NSCRegDbContext db)
        {
            _context = db;
        }

        /// <summary>
        /// Метод получения всех пользователей
        /// </summary>
        /// <param name="filter">Фильтр</param>
        /// <returns></returns>
        public async Task<UserListVm> GetAllPagedAsync(UserListFilter filter)
        {
            var regionTree = await new RegionService(_context).GetRegionTreeAsync().ConfigureAwait(false);

            var query = _context.Users.AsNoTracking();
            if (filter.Status.HasValue)
            {
                query = query.Where(u => u.Status == filter.Status.Value);
            }
            if (filter.RoleId != null)
            {
                query = query.Where(u => u.Roles.Any(v => v.RoleId == filter.RoleId));
            }
            if (filter.UserName != null)
            {
                query = query.Where(u => u.Name.Contains(filter.UserName));
            }
            if (filter.Description != null)
            {
                query = query.Where(u => u.Description.Contains(filter.Description));
            }

            var total = query.Count();

            var orderable = total == 0
                ? Array.Empty<UserListItemVm>().AsQueryable()
                : query.Select(UserListItemVm.Creator);

            if (filter.SortBy != null)
            {
                //TODO: USE LINQ DYNAMIC + ATTRIBUTES
                switch (filter.SortBy.UpperFirstLetter())
                {
                    case nameof(UserListItemVm.CreationDate):
                        orderable = Order(orderable, v => v.CreationDate, filter.SortAscending);
                        break;
                    case nameof(UserListItemVm.Description):
                        orderable = Order(orderable, v => v.Description, filter.SortAscending);
                        break;
                    default:
                        orderable = Order(orderable, v => v.Name, filter.SortAscending);
                        break;
                }
            }

            var users = orderable
                .Skip(Pagination.CalculateSkip(filter.PageSize, filter.Page, total))
                .Take(filter.PageSize);

            var usersList = users.ToList();

            string[][] filteredRegion = new string[][] { };
            if (regionTree != null)
            {
                var allRegions = regionTree.RegionNodes.Select(x => x.Name).ToArray();
                var userRegions = usersList.Select(x => x.Regions);
                var intersectedRegions = userRegions.Select(x =>
                    x.Intersect(allRegions));
                var selectedRegion = intersectedRegions.Select(x =>
                    x.ToArray().Length == allRegions.Length ? new[] { regionTree.Name} : x.ToArray()).ToArray();
                filteredRegion = selectedRegion;
            }

            var userIds = usersList.Select(v => v.Id).ToList();

            var roles = from userRole in _context.UserRoles
                join role in _context.Roles on userRole.RoleId equals role.Id
                where userIds.Contains(userRole.UserId)
                select new
                {
                    userRole.UserId,
                    role.Id,
                    role.Name
                };

            var lookup = roles.ToLookup(
                v => v.UserId,
                v => new UserRoleVm {Id = v.Id, Name = v.Name}
            );

            foreach (var user in usersList)
            {
                user.Roles = lookup[user.Id].ToList();
                user.Regions = null;
            }
            for (int i = 0; i < filteredRegion.Length; i++)
            {
                usersList[i].Regions = filteredRegion[i];
            }

            return UserListVm.Create(
                usersList,
                total,
                (int) Math.Ceiling((double) total / filter.PageSize)
            );
        }

        /// <summary>
        /// Метод получения пользователя
        /// </summary>
        /// <param name="id">Id пользователя</param>
        /// <returns></returns>
        public UserVm GetById(string id)
        {
            var user = _context.Users
                .Include(u => u.Roles)
                .Include(u => u.ActivitysCategoryUsers)
                .Include(x => x.UserRegions)
                .ThenInclude(x => x.Region)
                .FirstOrDefault(u => u.Id == id);
            if (user == null)
                throw new Exception(nameof(Resource.UserNotFoundError));

            var roleName = _context.Roles
                .Where(r => user.Roles.Any(ur => ur.RoleId == r.Id))
                .Select(r => r.Name).SingleOrDefault();
            return UserVm.Create(user, roleName);
        }

        /// <summary>
        /// Метод установки статуса пользователю
        /// </summary>
        /// <param name="id">Id пользователя</param>
        /// <param name="isSuspend">Флаг приостановленности</param>
        /// <returns></returns>
        public async Task SetUserStatus(string id, bool isSuspend)
        {
            var user = await _context.Users.FindAsync(id);
            if (user == null)
                throw new Exception(nameof(Resource.UserNotFoundError));

            var status = UserStatuses.Active;
            DateTime? date = null;
            if (isSuspend)
            {
                var adminRole = await _context.Roles.Include(r => r.Users).FirstOrDefaultAsync(
                    r => r.Name == DefaultRoleNames.Administrator);
                if (adminRole == null)
                    throw new Exception(nameof(Resource.SysAdminRoleMissingError));

                if (adminRole.Users.Any(ur => ur.UserId == user.Id)
                    && adminRole.Users.Count(us =>
                        _context.Users.Count(u => us.UserId == u.Id && u.Status == UserStatuses.Active) == 1) == 1)
                    throw new Exception(nameof(Resource.DeleteLastSysAdminError));

                status = UserStatuses.Suspended;
                date = DateTime.Now;
            }

            user.Status = status;
            user.SuspensionDate = date;
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Метод сортировки пользователей
        /// </summary>
        /// <typeparam name="T">Тип</typeparam>
        /// <param name="query">Запрос</param>
        /// <param name="selector">Селектор</param>
        /// <param name="asceding">Восходящий</param>
        /// <returns></returns>
        private static IQueryable<UserListItemVm> Order<T>(IQueryable<UserListItemVm> query,
            Expression<Func<UserListItemVm, T>> selector, bool asceding)
        {
            return asceding ? query.OrderBy(selector) : query.OrderByDescending(selector);
        }

        /// <summary>
        /// Метод получения системной функции по Id пользователя
        /// </summary>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<SystemFunctions[]> GetSystemFunctionsByUserId(string userId)
        {
            var access = await (from userRoles in _context.UserRoles
                join role in _context.Roles on userRoles.RoleId equals role.Id
                join user in _context.Users on userRoles.UserId equals user.Id
                where userRoles.UserId == userId && user.Status == UserStatuses.Active &&
                      role.Status == RoleStatuses.Active
                select role.AccessToSystemFunctions).ToListAsync();
            return
                access.Select(x => x.Split(','))
                    .SelectMany(x => x)
                    .Select(int.Parse)
                    .Cast<SystemFunctions>()
                    .ToArray();
        }

        /// <summary>
        /// Метод получения атрибутов доступа к данным
        /// </summary>
        /// <param name="userId">Id пользователя</param>
        /// <param name="type">Тип пользователя</param>
        /// <returns></returns>
        public async Task<DataAccessPermissions> GetDataAccessAttributes(string userId, StatUnitTypes? type)
        {
            var dataAccess = await (
                    from userRoles in _context.UserRoles
                    join role in _context.Roles on userRoles.RoleId equals role.Id
                    where userRoles.UserId == userId
                    select role.StandardDataAccessArray
                )
                .ToListAsync();

            var commonPermissions = new DataAccessPermissions(
                DataAccessAttributesProvider.CommonAttributes
                    .Select(v => new Permission(v.Name, true, false)));
            var permissions = DataAccessPermissions.Combine(dataAccess.Append(commonPermissions));

            if (type.HasValue)
            {
                var name = StatisticalUnitsTypeHelper.GetStatUnitMappingType(type.Value).Name;
                permissions = permissions.ForType(name);
            }
            return permissions;
        }

        /// <summary>
        /// Метод создания связи пользвателя к региону
        /// </summary>
        /// <param name="user">Пользватель</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        public async Task RelateUserRegionsAsync(User user, IUserSubmit data)
        {
            var oldUserRegions = await _context.UserRegions.Where(x => x.UserId == user.Id).ToListAsync();
            var regions = await _context.Regions.Where(v => data.UserRegions.Contains(v.Id)).ToListAsync();

            foreach (var oldUserRegion in oldUserRegions)
            {
                if (!data.UserRegions.Contains(oldUserRegion.RegionId))
                    _context.Remove(oldUserRegion);
            }
            foreach (var region in regions)
            {
                if (oldUserRegions.All(x => x.RegionId != region.Id))
                    _context.UserRegions.Add(new UserRegion
                    {
                        User = user,
                        UserId = user.Id,
                        Region = region,
                        RegionId = region.Id,
                    });
            }
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Creates/updates relationships between user and activity types
        /// </summary>
        /// <param name="user"></param>
        /// <param name="data"></param>
        /// <returns></returns>
        public async Task RelateUserActivityCategoriesAsync(User user, IUserSubmit data)
        {
            var oldActivityCategoryUsers =
                await _context.ActivityCategoryUsers.Where(x => x.UserId == user.Id).ToListAsync();
            var oldActivityCategoryUsersIds = oldActivityCategoryUsers.Select(x => x.ActivityCategoryId).ToList();

            if (data.IsAllActivitiesSelected)
            {
                var allActivityIds = (await _context.ActivityCategories.Select(x => x.Id).ToListAsync())
                    .Except(oldActivityCategoryUsersIds);

                foreach (var id in allActivityIds)
                    _context.ActivityCategoryUsers.Add(new ActivityCategoryUser
                    {
                        ActivityCategoryId = id,
                        UserId = user.Id
                    });
                await _context.SaveChangesAsync();
                return;
            }

            var all = await _context.ActivityCategories.ToListAsync();
            var newHierarchy = GetFullHierarchy(data.ActiviyCategoryIds.ToList(), all);

            var itemsToDelete = oldActivityCategoryUsers.Where(x => !newHierarchy.Contains(x.ActivityCategoryId));
            foreach (var item in itemsToDelete)
                _context.Remove(item);


            var itemsToAdd = newHierarchy.Except(oldActivityCategoryUsersIds);
            foreach (var id in itemsToAdd)
                _context.ActivityCategoryUsers.Add(new ActivityCategoryUser
                {
                    ActivityCategoryId = id,
                    UserId = user.Id
                });

            await _context.SaveChangesAsync();
        }

        private IEnumerable<int> GetFullHierarchy(List<int> categories, List<ActivityCategory> all)
        {
            return categories
                .SelectMany(x => GetHierarchy(x, all))
                .Concat(categories)
                .Distinct();
        }

        private IEnumerable<int> GetHierarchy(int id, List<ActivityCategory> all)
        {
            foreach (var activityCategory in all.Where(x => x.ParentId == id))
            {
                yield return activityCategory.Id;
                foreach (var catId in GetHierarchy(activityCategory.Id, all))
                {
                    yield return catId;
                }
            }
        }

        /// <summary>
        /// Determines if user belongs to specified role
        /// </summary>
        /// <param name="userId"></param>
        /// <param name="role"></param>
        /// <returns></returns>
        public async Task<bool> IsInRoleAsync(string userId, string role)
        {
            var roles = await _context.Roles.Include(x => x.Users).SingleAsync(x => x.Name == role);
            return roles.Users.Any(x => x.UserId == userId);
        }
    }
}
