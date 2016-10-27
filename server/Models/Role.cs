using Microsoft.AspNetCore.Identity.EntityFrameworkCore;

namespace Server.Models
{
    public class Role: IdentityRole
    {
        public string Description { get; set; }
    }
}
