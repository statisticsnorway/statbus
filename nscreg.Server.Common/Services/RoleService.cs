using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.CommandStack;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.ActivityCategories;
using nscreg.Server.Common.Models.Roles;

namespace nscreg.Server.Common.Services
{
    public class RoleService
    {
        private readonly ReadContext _readCtx;
        private readonly CommandContext _commandCtx;
        private readonly NSCRegDbContext _context;

        public RoleService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
            _readCtx = new ReadContext(dbContext);
            _commandCtx = new CommandContext(dbContext);
        }

        public RoleListVm GetAllPaged(PaginationModel model, bool onlyActive)
        {
            var listRoles = onlyActive
                ? _readCtx.Roles.Where(x => x.Status == RoleStatuses.Active)
                : _readCtx.Roles;
            var total = listRoles.Count();
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;
            var roles = listRoles
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .OrderBy(x => x.Name)
                .ToList();

            var rolesIds = roles.Select(v => v.Id).ToList();

            var usersCount =
            (from u in _readCtx.Users
                join ur in _readCtx.UsersRoles on u.Id equals ur.UserId
                join r in _readCtx.Roles on ur.RoleId equals r.Id
                where rolesIds.Contains(r.Id) && u.Status == UserStatuses.Active
                group r by r.Id
                into g
                select new {RoleId = g.Key, Count = g.Count()}).ToDictionary(v => v.RoleId, v => v.Count);

            foreach (var role in roles)
            {
                int value;
                usersCount.TryGetValue(role.Id, out value);
                role.ActiveUsers = value;
            }

            return RoleListVm.Create(roles.Select(RoleVm.Create), total,
                (int) Math.Ceiling((double) total / model.PageSize));
        }

        public RoleVm GetRoleById(string id)
        {
            var role = _readCtx.Roles
                .Include(x => x.ActivitysCategoryRoles)
                .ThenInclude(x => x.ActivityCategory)
                .FirstOrDefault(r => r.Id == id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            return RoleVm.Create(role);
        }

        public RoleVm Create(RoleSubmitM data)
        {
            if (_context.Roles.Any(r => r.Name == data.Name))
                throw new Exception(nameof(Resource.NameError));

            var role = new Role
            {
                Name = data.Name,
                Description = data.Description,
                AccessToSystemFunctionsArray = data.AccessToSystemFunctions,
                StandardDataAccessArray = data.StandardDataAccess.ToStringCollection(),
                NormalizedName = data.Name.ToUpper(),
                Status = RoleStatuses.Active,
            };

            _context.Roles.Add(role);
            RelateActivityCategories(role, data);
            _context.SaveChanges();

            return RoleVm.Create(role);
        }

        public void Edit(string id, RoleSubmitM data)
        {
            var role = _context.Roles
                .Include(x => x.ActivitysCategoryRoles)
                .ThenInclude(x => x.ActivityCategory)
                .FirstOrDefault(r => r.Id == id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            if (role.Name != data.Name
                && _context.Roles.Any(r => r.Name == data.Name))
                throw new Exception(nameof(Resource.NameError));

            role.Name = data.Name;
            role.AccessToSystemFunctionsArray = data.AccessToSystemFunctions;
            role.StandardDataAccessArray = data.StandardDataAccess.ToStringCollection();
            role.Description = data.Description;
            RelateActivityCategories(role, data);
            _context.SaveChanges();
        }

        public void RelateActivityCategories(Role role, RoleSubmitM data)
        {
            var oldActivityCategoryRoles = role.ActivitysCategoryRoles;
            var activityCategories = data.ActiviyCategoryIds
                .SelectMany(x =>
                    _context.ActivityCategories
                        .Include(r => r.ActivityCategoryRoles)
                        .Where(ax => ax.Id == x));

            foreach (var oldActivityCategoryRole in oldActivityCategoryRoles)
            {
                if (!data.ActiviyCategoryIds.Contains(oldActivityCategoryRole.ActivityCategoryId))
                    _context.Remove(oldActivityCategoryRole);
            }
            foreach (var activityCategory in activityCategories)
            {
                if (oldActivityCategoryRoles.All(x => x.ActivityCategoryId != activityCategory.Id))
                    _context.ActivityCategoryRoles.Add(new ActivityCategoryRole
                    {
                        ActivityCategory = activityCategory,
                        ActivityCategoryId = activityCategory.Id,
                        Role = role,
                        RoleId = role.Id
                    });
            }
        }

        public async Task ToggleSuspend(string id, RoleStatuses status)
        {
            var role = await _readCtx.Roles.Include(x => x.Users).FirstOrDefaultAsync(r => r.Id == id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            var userIds = role.Users.Select(ur => ur.UserId).ToArray();

            if (status == RoleStatuses.Suspended && userIds.Any() &&
                _readCtx.Users.Any(u => userIds.Contains(u.Id) && u.Status == UserStatuses.Active))
                throw new Exception(nameof(Resource.DeleteRoleError));

            if (status == RoleStatuses.Suspended && role.Name == DefaultRoleNames.SystemAdministrator)
                throw new Exception(nameof(Resource.DeleteSysAdminRoleError));

            await _commandCtx.ToggleSuspendRole(id, status);
        }

        public Task<List<ActivityCategoryVm>> FetchActivityTreeAsync() => _readCtx.ActivityCategories
            .Where(x => Regex.IsMatch(x.Code, @"[a-zA-Z]{1,2}")).OrderBy(x => x.Code)
            .Select(x => new ActivityCategoryVm
            {
                Id = x.Id.ToString(),
                Name = x.Name,
                Code = x.Code,
                Section = x.Section
            }).ToListAsync();
    }
}
