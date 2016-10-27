using System.ComponentModel.DataAnnotations;

namespace Server.ViewModels
{
    public class RoleViewModel
    {
        [Required]
        public string Name { get; set; }

        public string Description { get; set; }
    }
}
