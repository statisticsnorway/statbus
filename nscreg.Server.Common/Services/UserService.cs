using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.CommandStack;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Users;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services
{
    public class UserService : IUserService
    {
        private readonly CommandContext _commandCtx;
        private readonly ReadContext _readCtx;
        private readonly NSCRegDbContext _context;


        public UserService(NSCRegDbContext db)
        {
            _commandCtx = new CommandContext(db);
            _readCtx = new ReadContext(db);
            _context = db;
        }

        public UserListVm GetAllPaged(UserListFilter filter)
        {
            var query = _readCtx.Users;
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


            var total = query.Count();

            var orderable = total == 0
                ? Array.Empty<UserListItemVm>().AsQueryable()
                : query.Select(UserListItemVm.Creator);

            if (filter.SortColumn != null)
            {
                //TODO: USE LINQ DYNAMIC + ATTRIBUTES
                switch (filter.SortColumn.UpperFirstLetter())
                {
                    case nameof(UserListItemVm.Name):
                        orderable = Order(orderable, v => v.Name, filter.SortAscending);
                        break;
                    case nameof(UserListItemVm.CreationDate):
                        orderable = Order(orderable, v => v.CreationDate, filter.SortAscending);
                        break;
                }
            }


            var users = orderable.Skip(filter.PageSize * (filter.Page - 1))
                .Take(filter.PageSize);

            var usersList = users.ToList();

            var userIds = usersList.Select(v => v.Id).ToList();

            var roles = from userRole in _readCtx.UsersRoles
                join role in _readCtx.Roles on userRole.RoleId equals role.Id
                where userIds.Contains(userRole.UserId)
                select new
                {
                    userRole.UserId,
                    role.Id,
                    role.Name
                };

            var lookup = roles.ToLookup(
                v => v.UserId,
                v => new UserRoleVm() {Id = v.Id, Name = v.Name}
            );

            foreach (var user in usersList)
            {
                user.Roles = lookup[user.Id].ToList();
            }

            return UserListVm.Create(
                usersList,
                total,
                (int) Math.Ceiling((double) (total) / filter.PageSize)
            );
        }

        public UserVm GetById(string id)
        {
            var user = _readCtx.Users
                .Include(u => u.Roles)
                .Include(x => x.UserRegions)
                .ThenInclude(x => x.Region)
                .FirstOrDefault(u => u.Id == id);
            if (user == null)
                throw new Exception(nameof(Resource.UserNotFoundError));

            var roleNames = _readCtx.Roles
                .Where(r => user.Roles.Any(ur => ur.RoleId == r.Id))
                .Select(r => r.Name);
            return UserVm.Create(user, roleNames);
        }

        public async Task SetUserStatus(string id, bool isSuspend)
        {
            var user = _readCtx.Users.FirstOrDefault(u => u.Id == id);
            if (user == null)
                throw new Exception(nameof(Resource.UserNotFoundError));

            if (isSuspend)
            {
                var adminRole = _readCtx.Roles.Include(r => r.Users).FirstOrDefault(
                 r => r.Name == DefaultRoleNames.SystemAdministrator);
                if (adminRole == null)
                    throw new Exception(nameof(Resource.SysAdminRoleMissingError));

                if (adminRole.Users.Any(ur => ur.UserId == user.Id)
                    && adminRole.Users.Count(us=> _readCtx.Users.Count(u=> us.UserId == u.Id && u.Status == UserStatuses.Active) == 1) == 1)
                    throw new Exception(nameof(Resource.DeleteLastSysAdminError));
            }

            await _commandCtx.SetUserStatus(id, isSuspend ? UserStatuses.Suspended : UserStatuses.Active);
        }

        private IQueryable<UserListItemVm> Order<T>(IQueryable<UserListItemVm> query, Expression<Func<UserListItemVm, T>> selector, bool asceding)
        {
            return asceding ? query.OrderBy(selector) : query.OrderByDescending(selector);
        }

        public async Task<SystemFunctions[]> GetSystemFunctionsByUserId(string userId)
        {
            var access = await (from userRoles in _readCtx.UsersRoles
                                join role in _readCtx.Roles on userRoles.RoleId equals role.Id
                                join user in _readCtx.Users on userRoles.UserId equals user.Id
                                where userRoles.UserId == userId && user.Status == UserStatuses.Active && role.Status == RoleStatuses.Active
                                select role.AccessToSystemFunctions).ToListAsync();
            return
                access.Select(x => x.Split(','))
                    .SelectMany(x => x)
                    .Select(int.Parse)
                    .Cast<SystemFunctions>()
                    .ToArray();
        }

        public async Task<ISet<string>> GetDataAccessAttributes(string userId, StatUnitTypes? type)
        {
            var dataAccess = await (
                from userRoles in _readCtx.UsersRoles
                join role in _readCtx.Roles on userRoles.RoleId equals role.Id
                where userRoles.UserId == userId
                select role.StandardDataAccess
            ).Union(
                from user in _readCtx.Users
                where user.Id == userId
                select user.DataAccess
            ).ToListAsync();

            var list = dataAccess.Select(v => (v ?? "").Split(',')).SelectMany(v => v);
            //Add common attributes
            list = list.Concat(DataAccessAttributesProvider.CommonAttributes.Select(v => v.Name));
            if (type.HasValue)
            {
                var name = StatisticalUnitsTypeHelper.GetStatUnitMappingType(type.Value).Name;
                list = list.Where(v => v.StartsWith($"{name}."));
            }
            return list.ToImmutableHashSet();
        }

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
    }
}
