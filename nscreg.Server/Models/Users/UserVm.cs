using System.Collections.Generic;
using nscreg.Data.Entities;
using nscreg.Data.Constants;

namespace nscreg.Server.Models.Users
{
    public class UserVm
    {
        public static UserVm Create(User user, IEnumerable<string> roles) => new UserVm
        {
            Id = user.Id,
            Login = user.Login,
            Name = user.Name,
            Phone = user.PhoneNumber,
            Email = user.Email,
            Description = user.Description,
            AssignedRoles = roles,
            Status = user.Status,
            DataAccess = user.DataAccessArray,
        };

        public string Id { get; private set; }
        public string Login { get; private set; }
        public string Name { get; private set; }
        public string Phone { get; private set; }
        public string Email { get; private set; }
        public string Description { get; private set; }
        public IEnumerable<string> AssignedRoles { get; private set; }
        public IEnumerable<int> DataAccess { get; private set; }
        public UserStatuses Status { get; private set; }
    }
}
