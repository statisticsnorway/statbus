using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Models.Users
{
    public class UserListItemVm
    {
        public static UserListItemVm Create(User user)
            => new UserListItemVm
            {
                Id = user.Id,
                Login = user.Login,
                Name = user.Name,
                Phone = user.PhoneNumber,
                Email = user.Email,
                Description = user.Description,
                Status = user.Status,
                RegionId = user.RegionId
            };

        public string Id { get; private set; }
        public string Login { get; private set; }
        public string Name { get; private set; }
        public string Phone { get; private set; }
        public string Email { get; private set; }
        public string Description { get; private set; }
        public UserStatuses Status { get; private set; }
        public int? RegionId { get; private set; }
    }
}
