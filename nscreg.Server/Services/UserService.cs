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
        private readonly ReadContext readCtx;

        public UserService(NSCRegDbContext db)
        {
            readCtx = new ReadContext(db);
        }

        public UsersListVm GetAllPaged(int page, int pageSize)
        {
            var activeUsers = readCtx.Users.Where(u => u.Status == UserStatuses.Active);
            var resultGroup = activeUsers
                .Skip(page * pageSize)
                .Take(page)
                .GroupBy(p => new { Total = activeUsers.Count() })
                .First();

            return UsersListVm.Create(
                resultGroup.Select(UserListItemVm.Create),
                resultGroup.Key.Total,
                (int)Math.Ceiling((double)resultGroup.Key.Total / pageSize));
        }

        public UserVm GetById(string id)
        {
            var user = readCtx.Users.FirstOrDefault(u => u.Id == id && u.Status == UserStatuses.Active);
            if (user == null)
                throw new Exception("user not found");
            var roleNames = readCtx.Roles
                .Where(r => user.Roles.Any(ur => ur.RoleId == r.Id))
                .Select(r => r.Name);
            return UserVm.Create(user, roleNames);
        }
    }
}
