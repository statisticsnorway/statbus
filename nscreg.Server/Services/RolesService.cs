using nscreg.CommandStack;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.ReadStack;
using nscreg.Server.Models.Roles;
using System;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Server.Services
{
    public class RolesService
    {
        private readonly ReadContext readCtx;
        private readonly CommandContext commandCtx;

        public RolesService(NSCRegDbContext dbContext)
        {
            readCtx = new ReadContext(dbContext);
            commandCtx = new CommandContext(dbContext);
        }

        public RolesListVm GetAllPaged(int page, int pageSize)
        {
            var allRolesQuery = readCtx.Roles;
            var resultGroup = allRolesQuery
                .Skip(page * pageSize)
                .Take(page)
                .GroupBy(p => new { Total = allRolesQuery.Count() })
                .First();
            return RolesListVm.Create(
                resultGroup.Select(RoleVm.Create),
                resultGroup.Key.Total,
                (int)Math.Ceiling((double)resultGroup.Key.Total / pageSize));
        }

        public RoleVm GetRoleById(string id)
        {
            var role = readCtx.Roles.SingleOrDefault(r => r.Id == id);
            if (role == null) throw new Exception("role not found");
            return RoleVm.Create(role);
        }

        public IEnumerable<UserItem> GetUsersByRole(string id)
        {
            var role = readCtx.Roles.SingleOrDefault(r => r.Id == id);
            if (role == null) throw new Exception("role not found");
            try
            {
                return readCtx.Users
                    .Where(u => u.Status == UserStatuses.Active && u.Roles.Any(r => role.Id == r.RoleId))
                    .Select(u => new UserItem
                    {
                        Id = u.Id,
                        Name = u.Name,
                        Descritpion = u.Description
                    });
            }
            catch
            {
                throw new Exception("error fetching users");
            }
        }

        public void Delete(string id)
        {
            var role = readCtx.Roles.SingleOrDefault(r => r.Id == id);
            if (role == null) throw new Exception("role not found");
            if (role.Users.Any()) throw new Exception("can't delete role with existing users");
            if (role.Name == DefaultRoleNames.SystemAdministrator) throw new Exception("Can't delete system administrator role");
            commandCtx
        }
    }
}
