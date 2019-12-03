using System.Collections.Generic;
using nscreg.Server.Common.Models.Regions;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// View user list model
    /// </summary>
    public class UserListVm
    {
        /// <summary>
        /// Method for creating a view model of a user list
        /// </summary>
        /// <param name="users">users</param>
        /// <param name="totalCount">total counts</param>
        /// <param name="totalPages">total pages</param>
        /// <returns></returns>
        public static UserListVm Create(IEnumerable<UserListItemVm> users, RegionNode allRegions, int totalCount, int totalPages)
            => new UserListVm
            {
                Result = users,
                AllRegions = allRegions,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<UserListItemVm> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
        public RegionNode AllRegions { get; private set; }
    }
}
