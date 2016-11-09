using System.ComponentModel.DataAnnotations;

namespace Server.Models
{
    public class LoginVm
    {
        [Required]
        public string Login { get; set; }

        [Required, DataType(DataType.Password)]
        public string Password { get; set; }

        public string RedirectUrl { get; set; }

        public bool RememberMe { get; set; } = false;
    }
}
