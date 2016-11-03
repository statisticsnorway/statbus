using Server.Data;
using Server.Data.Defaults;

namespace Server.Models.Users
{
    public class UserListItemVm
    {
        public static UserListItemVm Create(User user) => new UserListItemVm
        {
            Id = user.Id,
            Login = user.Login,
            Name = user.Name,
            Phone = user.PhoneNumber,
            Email = user.Email,
            Description = user.Description,
            Status = user.Status,
        };

        public string Id { get; set; }
        public string Login { get; set; }
        public string Name { get; set; }
        public string Phone { get; set; }
        public string Email { get; set; }
        public string Description { get; set; }
        public UserStatuses Status { get; set; }
    }
}
