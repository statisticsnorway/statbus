using nscreg.CommandStack;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.ReadStack;
using nscreg.Server.Models.Users;
using System;
using System.Linq;

namespace nscreg.Server.Services
{
    public class UserService
    {
        private readonly CommandContext _commandCtx;
        private readonly ReadContext _readCtx;

        public UserService(NSCRegDbContext db)
        {
            _commandCtx = new CommandContext(db);
            _readCtx = new ReadContext(db);
        }

        public UserListVm GetAllPaged(int page, int pageSize)
        {
            var activeUsers = _readCtx.Users.Where(u => u.Status == UserStatuses.Active);
            var resultGroup = activeUsers
                .Skip(pageSize * page)
                .Take(pageSize)
                .GroupBy(p => new { Total = activeUsers.Count() })
                .First();

            return UserListVm.Create(
                resultGroup.Select(UserListItemVm.Create),
                resultGroup.Key.Total,
                (int)Math.Ceiling((double)resultGroup.Key.Total / pageSize));
        }

        public UserVm GetById(string id)
        {
            var user = _readCtx.Users.FirstOrDefault(u => u.Id == id && u.Status == UserStatuses.Active);
            if (user == null)
                throw new Exception("user not found");

            var roleNames = _readCtx.Roles
                .Where(r => user.Roles.Any(ur => ur.RoleId == r.Id))
                .Select(r => r.Name);
            return UserVm.Create(user, roleNames);
        }

        public void Suspend(string id)
        {
            var user = _readCtx.Users.FirstOrDefault(u => u.Id == id);
            if (user == null)
                throw new Exception("user not found");

            var adminRole = _readCtx.Roles.FirstOrDefault(
                r => r.Name == DefaultRoleNames.SystemAdministrator);
            if (adminRole == null)
                throw new Exception("system administrator role is missing");

            if (adminRole.Users.Any(ur => ur.UserId == user.Id)
                && adminRole.Users.Count() == 1)
                throw new Exception("can't delete very last system administrator");

            _commandCtx.SuspendUser(id);
        }
    }
}
