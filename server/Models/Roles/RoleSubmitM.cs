using System.ComponentModel.DataAnnotations;

namespace Server.Models.Roles
{
    public class RoleSubmitM
    {
        [Required]
        public string Name { get; set; }

        public string Description { get; set; }
    }
}
