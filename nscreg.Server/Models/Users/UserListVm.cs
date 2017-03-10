using System.Collections.Generic;

namespace nscreg.Server.Models.Users
{
    public class UserListVm
    {
        public static UserListVm Create(IEnumerable<UserListItemVm> users, int totalCount, int totalPages)
            => new UserListVm
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
