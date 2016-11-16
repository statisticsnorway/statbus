using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;
using nscreg.Data.Constants;

namespace nscreg.Server.Models.Users
{
    public class UsersListVm
    {
        public static UsersListVm Create(DatabaseContext db, int page, int pageSize, bool showAll)
        {
            var queriedUsers = db.Users.Where(u => showAll || u.Status == UserStatuses.Active);
            return new UsersListVm
            {
                Result = queriedUsers
                    .Skip(page*pageSize)
                    .Take(pageSize)
                    .Select(u => UserListItemVm.Create(u)),
                TotalCount = queriedUsers.Count(),
                TotalPages = (int) Math.Ceiling((double) queriedUsers.Count()/pageSize)
            };
        }

        public IEnumerable<UserListItemVm> Result { get; set; }
        public int TotalCount { get; set; }
        public int TotalPages { get; set; }
    }
}
