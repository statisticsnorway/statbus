using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Account
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
