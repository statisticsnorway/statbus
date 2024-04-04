using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Text;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Users;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities;
using nscreg.Utilities.Extensions;


namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// User service
    /// </summary>
    public class UserService : IUserService
    {
        private readonly NSCRegDbContext _context;
        private readonly RegionService _regionsService;
        private readonly IMapper _mapper;

        public UserService(NSCRegDbContext db, IMapper mapper)
        {
            _context = db;
            _mapper = mapper;
            _regionsService = new RegionService(db, _mapper);
        }

        /// <summary>
        /// Method to get all users
        /// </summary>
        /// <param name = "filter"> Filter </param>
        /// <returns> </returns>
        public async Task<UserListVm> GetAllPagedAsync(UserListFilter filter)
        {
            var query = _context.Users.AsNoTracking();
            if (filter.Status.HasValue)
            {
                query = query.Where(u => u.Status == filter.Status.Value);
            }
            if (filter.RoleId != null)
            {
                query = query.Where(u => u.UserRoles.Any(v => v.RoleId == filter.RoleId));
            }
            if (filter.UserName != null)
            {
                query = query.Where(u => u.Name.ToLower().Contains(filter.UserName.ToLower()));
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
                    case nameof(UserListItemVm.Name):
                        orderable = Order(orderable, v => v.Name, filter.SortAscending);
                        break;
                    case nameof(UserListItemVm.CreationDate):
                        orderable = Order(orderable, v => v.CreationDate, filter.SortAscending);
                        break;
                    case nameof(UserListItemVm.Description):
                        orderable = Order(orderable, v => v.Description, filter.SortAscending);
                        break;
                    default:
                        orderable = Order(orderable, v => v.Status, filter.SortAscending);
                        break;
                }
            }

            var users = orderable
                .Skip(Pagination.CalculateSkip(filter.PageSize, filter.Page, total))
                .Take(filter.PageSize);

            var usersList = users.ToList();

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
            var allRegions = await _regionsService.GetAllRegionTreeAsync(nameof(Resource.UserRegions));
            foreach (var user in usersList)
            {
                user.Roles = lookup[user.Id].ToList();
            }

            return UserListVm.Create(
                usersList,
                allRegions,
                total,
                (int) Math.Ceiling((double) total / filter.PageSize)
            );
        }

        /// <summary>
        /// Method to get the user
        /// </summary>
        /// <param name = "id"> User Id </param>
        /// <returns> </returns>
        public UserVm GetUserVmById(string id)
        {
            var user = GetUserById(id);
            var roleId = _context.UserRoles.First(x => x.UserId == id).RoleId;
            var roleName = _context.Roles.FirstOrDefault(x => x.Id == roleId)?.Name;

            return UserVm.Create(user, roleName);
        }

        public User GetUserById(string id)
        {
            var user = _context.Users
                .Include(u => u.UserRoles)
                .Include(u => u.ActivityCategoryUsers)
                .Include(x => x.UserRegions)
                .ThenInclude(x => x.Region)
                // There are few rows after the join, so load all in a single query.
                .AsSingleQuery()
                .FirstOrDefault(u => u.Id == id);
            if (user == null)
                throw new Exception(nameof(Resource.UserNotFoundError));

            return user;
        }

         /// <summary>
         /// Method for setting status to user
         /// </summary>
         /// <param name = "id"> User Id </param>
         /// <param name = "isSuspend"> Pause flag </param>
         /// <returns> </returns>
        public async Task SetUserStatus(string id, bool isSuspend)
        {
            var user = await _context.Users.FindAsync(id);
            if (user == null)
                throw new Exception(nameof(Resource.UserNotFoundError));

            var status = UserStatuses.Active;
            DateTime? date = null;
            if (isSuspend)
            {
                var adminRole = await _context.Roles.Include(r => r.UserRoles).FirstOrDefaultAsync(
                    r => r.Name == DefaultRoleNames.Administrator);
                if (adminRole == null)
                    throw new Exception(nameof(Resource.SysAdminRoleMissingError));

                if (adminRole.UserRoles.Any(ur => ur.UserId == user.Id)
                    && adminRole.UserRoles.Count(us =>
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
         /// User sorting method
         /// </summary>
         /// <typeparam name = "T"> Type </typeparam>
         /// <param name = "query"> Request </param>
         /// <param name = "selector"> Selector </param>
         /// <param name = "asceding"> Ascending </param>
         /// <returns> </returns>
        private static IQueryable<UserListItemVm> Order<T>(IQueryable<UserListItemVm> query,
            Expression<Func<UserListItemVm, T>> selector, bool asceding)
        {
            return asceding ? query.OrderBy(selector) : query.OrderByDescending(selector);
        }

         /// <summary>
         /// Method for obtaining a system function by user Id
         /// </summary>
         /// <param name = "userId"> User Id </param>
         /// <returns> </returns>
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
         /// Method for obtaining data access attributes
         /// </summary>
         /// <param name = "userId"> User Id </param>
         /// <param name = "type"> User type </param>
         /// <returns> </returns>
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
                    .Select(v => new Permission(v.Name, true, true)));
            var permissions = DataAccessPermissions.Combine(dataAccess.Append(commonPermissions));

            if (type.HasValue)
            {
                var name = StatisticalUnitsTypeHelper.GetStatUnitMappingType(type.Value).Name;
                permissions = permissions.ForType(name);
            }
            return permissions;
        }

         /// <summary>
         /// Method for creating a user relationship to a region
         /// </summary>
         /// <param name = "user"> User </param>
         /// <param name = "data"> Data </param>
         /// <returns> </returns>
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

        private static string GetIdsString(List<int> ids, int first, int count)
        {
            StringBuilder result = new StringBuilder();
            for (int i = first; i < first + count; i++)
            {
                if (i > first)
                    result.Append(',');
                result.Append(ids[i]);
            }
            return result.ToString();
        }

        /// <summary>
        /// Creates / updates relationships between user and activity types
        /// </summary>
        /// <param name = "user"> </param>
        /// <param name = "data"> </param>
        /// <returns> </returns>
        public async Task RelateUserActivityCategoriesAsync(User user, IUserSubmit data)
        {
            var activityCategories = await _context.ActivityCategoryUsers.Where(x => x.UserId == user.Id).ToListAsync();
            var oldActivityCategoryUsersIds =
                activityCategories.Select(x => x.ActivityCategoryId).Distinct().ToList();

            var checkForChange = oldActivityCategoryUsersIds.Intersect(data.ActivityCategoryIds).Count() ==
                            oldActivityCategoryUsersIds.Count;

            if (oldActivityCategoryUsersIds.Count == 0 || !checkForChange)
            {
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

                var allActivityCategories = await _context.ActivityCategories.ToListAsync();
                var newHierarchy = new HashSet<int>(GetFullHierarchy(data.ActivityCategoryIds.ToList(), allActivityCategories));

                var itemIdsToDelete = activityCategories.Where(x => !newHierarchy.Contains(x.ActivityCategoryId)).ToList();
                if (itemIdsToDelete.Any())
                {
                    _context.RemoveRange(itemIdsToDelete);
                }

                var itemsToAdd = newHierarchy.Except(oldActivityCategoryUsersIds).Distinct().ToList();
                foreach (var id in itemsToAdd)
                {
                    await _context.ActivityCategoryUsers.AddAsync(new ActivityCategoryUser
                    {
                        ActivityCategoryId = id,
                        UserId = user.Id
                    });
                }

                await _context.SaveChangesAsync();
            }
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
            var roles = await _context.Roles.Include(x => x.UserRoles).SingleAsync(x => x.Name == role);
            return roles.UserRoles.Any(x => x.UserId == userId);
        }

        /// <summary>
        /// Verification method of existing user login
        /// </summary>
        /// <param name="login"></param>
        /// <returns></returns>
        public async Task<bool> IsLoginExist(string login)
        {
            var allusers = await _context.Users.ToListAsync();
            var userExist = allusers.Any(x => x.Login == login);
            return userExist;
        }
    }
}
