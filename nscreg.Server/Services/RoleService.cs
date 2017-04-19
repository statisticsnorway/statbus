using nscreg.CommandStack;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.Roles;
using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Resources.Languages;

namespace nscreg.Server.Services
{
    public class RoleService
    {
        private readonly ReadContext _readCtx;
        private readonly CommandContext _commandCtx;

        public RoleService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
            _commandCtx = new CommandContext(dbContext);
        }

        public RoleListVm GetAllPaged(int page, int pageSize, bool onlyActive)
        {
            var listRoles = onlyActive
                ? _readCtx.Roles.Where(x => x.Status == RoleStatuses.Active)
                : _readCtx.Roles
                ;
            var resultGroup = listRoles
                .Skip(pageSize * page)
                .Take(pageSize)
                .GroupBy(p => new {Total = listRoles.Count()})
                .FirstOrDefault();

            var roles = resultGroup.Select(v => v.Id).ToList();

            var usersCount =
            (from u in _readCtx.Users
                join ur in _readCtx.UsersRoles on u.Id equals ur.UserId
                join r in _readCtx.Roles on ur.RoleId equals r.Id
                where roles.Contains(r.Id) && u.Status == UserStatuses.Active
                group r by r.Id
                into g
                select new {RoleId = g.Key, Count = g.Count()}).ToDictionary(v => v.RoleId, v => v.Count);

            foreach (var role in resultGroup)
            {
                int value;
                usersCount.TryGetValue(role.Id, out value);
                role.ActiveUsers = value;
            }

            return RoleListVm.Create(
                resultGroup.Select(RoleVm.Create),
                resultGroup.Key.Total,
                (int)Math.Ceiling((double)resultGroup.Key.Total / pageSize));
        }

        public RoleVm GetRoleById(string id)
        {
            var role = _readCtx.Roles.FirstOrDefault(r => r.Id == id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            return RoleVm.Create(role);
        }

        public RoleVm Create(RoleSubmitM data)
        {
            if (_readCtx.Roles.Any(r => r.Name == data.Name))
                throw new Exception(nameof(Resource.NameError));

            var role = new Role
            {
                Name = data.Name,
                Description = data.Description,
                AccessToSystemFunctionsArray = data.AccessToSystemFunctions,
                StandardDataAccessArray = data.StandardDataAccess.ToStringCollection(),
                NormalizedName = data.Name.ToUpper(),
                Status = RoleStatuses.Active
            };

            _commandCtx.CreateRole(role);

            return RoleVm.Create(role);
        }

        public void Edit(string id, RoleSubmitM data)
        {
            var role = _readCtx.Roles.FirstOrDefault(r => r.Id == id);
            if (role == null)
                throw new Exception(nameof(Resource.RoleNotFound));

            if (role.Name != data.Name
                && _readCtx.Roles.Any(r => r.Name == data.Name))
                throw new Exception(nameof(Resource.NameError));

            role.Name = data.Name;
            role.AccessToSystemFunctionsArray = data.AccessToSystemFunctions;
            role.StandardDataAccessArray = data.StandardDataAccess.ToStringCollection();
            role.Description = data.Description;

            _commandCtx.UpdateRole(role);
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
    }
}