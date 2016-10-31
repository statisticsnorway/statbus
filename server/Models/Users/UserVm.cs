using System.Collections.Generic;
using System.Linq;
using Server.Data;

namespace Server.Models.Users
{
    public class UserVm
    {
        public static UserVm Create(User user, DatabaseContext db) => new UserVm
        {
            Id = user.Id,
            Login = user.Login,
            Name = user.Name,
            Phone = user.PhoneNumber,
            Email = user.Email,
            Description = user.Description,
            AssignedRoles = db.Roles.Where(r => user.Roles.Any(ur => r.Id == ur.RoleId)).Select(r => r.Name)
        };

        public string Id { get; set; }
        public string Login { get; set; }
        public string Name { get; set; }
        public string Phone { get; set; }
        public string Email { get; set; }
        public string Description { get; set; }
        public IEnumerable<string> AssignedRoles { get; set; }
    }
}
