using Microsoft.AspNetCore.Identity.EntityFrameworkCore;

namespace Server.Models
{
    public class User : IdentityUser
    {
        public string Description { get; set; }
        public UserStatus Status { get; set; }
    }
}
