using System.Collections.Generic;

namespace nscreg.Server.Models.Roles
{
    public class RolesListVm
    {
        public static RolesListVm Create(IEnumerable<RoleVm> roles, int totalCount, int totalPages) =>
            new RolesListVm
            {
                Result = roles,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<RoleVm> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
    }
}
