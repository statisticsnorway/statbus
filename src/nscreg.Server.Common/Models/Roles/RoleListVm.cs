using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Roles
{
    public class RoleListVm
    {
        public static RoleListVm Create(IEnumerable<RoleVm> roles, int totalCount, int totalPages) =>
            new RoleListVm
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
