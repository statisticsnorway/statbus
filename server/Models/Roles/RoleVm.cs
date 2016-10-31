using Server.Data;

namespace Server.Models.Roles
{
    public class RoleVm
    {
        public static RoleVm Create(Role role) => new RoleVm
        {
            Id = role.Id,
            Name = role.Name,
            Description = role.Description,
        };

        public string Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
    }
}
