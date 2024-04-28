using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataAccess;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// View user model
    /// </summary>
    public class UserVm
    {
        /// <summary>
        /// Method for creating a user model view
        /// </summary>
        /// <param name="user"></param>
        /// <param name="roles"></param>
        /// <returns></returns>
        public static UserVm Create(User user, string roles) => new UserVm
        {
            Id = user.Id,
            Login = user.Login,
            Name = user.Name,
            Phone = user.PhoneNumber,
            Email = user.Email,
            Description = user.Description,
            AssignedRole = roles,
            Status = user.Status,
            DataAccess = DataAccessModel.FromString(user.DataAccess),
            UserRegions = user.UserRegions.Select(x => x.RegionId.ToString()).ToList(),
            ActivityCategoryIds = user.ActivityCategoryUsers.Select(x=>x.ActivityCategoryId.ToString()).ToList()
        };

        public string Id { get; private set; }
        public string Login { get; private set; }
        public string Name { get; private set; }
        public string Phone { get; private set; }
        public string Email { get; private set; }
        public string Description { get; private set; }
        public string AssignedRole { get; private set; }
        public DataAccessModel DataAccess { get; private set; }
        public UserStatuses Status { get; private set; }
        public ICollection<string> UserRegions { get; set; }
        public ICollection<string> ActivityCategoryIds { get; set; }

    }
}
