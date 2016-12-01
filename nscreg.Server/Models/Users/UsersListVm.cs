using System.Collections.Generic;

namespace nscreg.Server.Models.Users
{
    public class UsersListVm
    {
        public static UsersListVm Create(IEnumerable<UserListItemVm> users, int totalCount, int totalPages)
            => new UsersListVm
            {
                Result = users,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<UserListItemVm> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
    }
}
