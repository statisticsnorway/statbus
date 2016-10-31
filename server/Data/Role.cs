using Microsoft.AspNetCore.Identity.EntityFrameworkCore;

namespace Server.Data
{
    public class Role: IdentityRole
    {
        public string Description { get; set; }
    }
}
