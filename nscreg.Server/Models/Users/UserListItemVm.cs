using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Models.Users
{
    public class UserListItemVm
    {
        public static readonly Expression<Func<User, UserListItemVm>> Creator =
            user => new UserListItemVm
            {
                Id = user.Id,
                Login = user.Login,
                Name = user.Name,
                Phone = user.PhoneNumber,
                Email = user.Email,
                Description = user.Description,
                Status = user.Status,
                CreationDate = user.CreationDate,
                SuspensionDate = user.SuspensionDate,
                RegionName = user.Region.Name,
            };

        public string Id { get; private set; }
        public string Login { get; private set; }
        public string Name { get; private set; }
        public string Phone { get; private set; }
        public string Email { get; private set; }
        public string Description { get; private set; }
        public UserStatuses Status { get; private set; }
        public DateTime CreationDate { get; private set; }
        public DateTime? SuspensionDate { get; private set; }
        public string RegionName { get; private set; }
        public List<UserRoleVm> Roles { get; set; }
    }
}
