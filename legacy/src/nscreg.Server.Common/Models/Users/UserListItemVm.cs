using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// View user unit list model
    /// </summary>
    public class UserListItemVm
    {
        /// <summary>
        /// Method for creating a view model of a list of user units
        /// </summary>
        public static readonly Expression<Func<User, UserListItemVm>> Creator =
            user => new UserListItemVm
            {
                Id = user.Id,
                Name = user.Name,
                Description = user.Description,
                Status = user.Status,
                CreationDate = user.CreationDate,
                SuspensionDate = user.SuspensionDate,
                Regions = user.UserRegions.Select(x => x.Region.Id).ToArray()
            };

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Description { get; private set; }
        public UserStatuses Status { get; private set; }
        public DateTimeOffset CreationDate { get; private set; }
        public DateTimeOffset? SuspensionDate { get; private set; }
        public List<UserRoleVm> Roles { get; set; }
        public int[] Regions { get; set; }
    }
}
