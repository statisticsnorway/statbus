using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.Users
{
    public class UserListItemVm
    {
        public static readonly Expression<Func<User, UserListItemVm>> Creator =
            user => new UserListItemVm
            {
                Id = user.Id,
                Name = user.Name,
                Description = user.Description,
                Status = user.Status,
                CreationDate = user.CreationDate,
                SuspensionDate = user.SuspensionDate,
            };

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Description { get; private set; }
        public UserStatuses Status { get; private set; }
        public DateTime CreationDate { get; private set; }
        public DateTime? SuspensionDate { get; private set; }
        public List<UserRoleVm> Roles { get; set; }
    }
}
