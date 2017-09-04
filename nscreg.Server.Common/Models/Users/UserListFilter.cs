using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.Users
{
    public class UserListFilter : PaginatedQueryM
    {
        public string UserName { get; set; }
        public string RoleId { get; set; }
        public UserStatuses? Status { get; set; }
    }
}
