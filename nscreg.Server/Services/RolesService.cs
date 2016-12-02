using nscreg.CommandStack;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.Roles;
using System;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Server.Services
{
    public class RolesService
    {
        private readonly ReadContext _readCtx;
        private readonly CommandContext _commandCtx;

        public RolesService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
            _commandCtx = new CommandContext(dbContext);
        }

        public RolesListVm GetAllPaged(int page, int pageSize)
        {
            var activeRoles = _readCtx.Roles.Where(r => r.Status == RoleStatuses.Active);
            var resultGroup = activeRoles
                .Skip(pageSize * page)
                .Take(pageSize)
                .GroupBy(p => new { Total = activeRoles.Count() })
                .First();

            return RolesListVm.Create(
                resultGroup.Select(RoleVm.Create),
                resultGroup.Key.Total,
                (int)Math.Ceiling((double)resultGroup.Key.Total / pageSize));
        }

        public RoleVm GetRoleById(string id)
        {
            var role = _readCtx.Roles.FirstOrDefault(r => r.Id == id && r.Status == RoleStatuses.Active);
            if (role == null)
                throw new Exception("role not found");

            return RoleVm.Create(role);
        }

        public IEnumerable<UserItem> GetUsersByRole(string id)
        {
            var role = _readCtx.Roles.FirstOrDefault(r => r.Id == id);
            if (role == null) throw new Exception("role not found");

            try
            {
                return _readCtx.Users
                    .Where(u =>
                        u.Status == UserStatuses.Active
                        && u.Roles.Any(r => role.Id == r.RoleId))
                    .Select(UserItem.Create);
            }
            catch
            {
                throw new Exception("error fetching users");
            }
        }

        public RoleVm Create(RoleSubmitM data)
        {
            if (_readCtx.Roles.Any(r => r.Name == data.Name))
                throw new Exception("name is already taken");

            var role = new Role
            {
                Name = data.Name,
                Description = data.Description,
                AccessToSystemFunctionsArray = data.AccessToSystemFunctions,
                StandardDataAccessArray = data.StandardDataAccess,
                NormalizedName = data.Name.ToUpper(),
            };

            _commandCtx.CreateRole(role);

            return RoleVm.Create(role);
        }

        public void Edit(string id, RoleSubmitM data)
        {
            var role = _readCtx.Roles.FirstOrDefault(r => r.Id == id);
            if (role == null)
                throw new Exception("role not found");

            if (_readCtx.Roles.Any(r => r.Name == data.Name))
                throw new Exception("name is already taken");

            role.Name = data.Name;
            role.AccessToSystemFunctionsArray = data.AccessToSystemFunctions;
            role.StandardDataAccessArray = data.StandardDataAccess;
            role.Description = data.Description;

            _commandCtx.UpdateRole(role);
        }

        public void Suspend(string id)
        {
            var role = _readCtx.Roles.FirstOrDefault(r => r.Id == id);
            if (role == null)
                throw new Exception("role not found");

            var userIds = role.Users.Select(ur => ur.UserId);
            if (userIds.Any() &&
                _readCtx.Users.Any(u => userIds.Contains(u.Id) && u.Status == UserStatuses.Active))
                throw new Exception("can't delete role with existing users");

            if (role.Name == DefaultRoleNames.SystemAdministrator)
                throw new Exception("can't delete system administrator role");

            _commandCtx.SuspendRole(id);
        }
    }
}
