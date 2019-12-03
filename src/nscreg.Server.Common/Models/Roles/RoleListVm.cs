using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Roles
{
    /// <summary>
    /// View role list model
    /// </summary>
    public class RoleListVm
    {
        /// <summary>
        /// Method for creating a view of the role list model
        /// </summary>
        /// <param name="roles">Roles</param>
        /// <param name="totalCount">Total count</param>
        /// <param name="totalPages">Total pages</param>
        /// <returns></returns>
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
