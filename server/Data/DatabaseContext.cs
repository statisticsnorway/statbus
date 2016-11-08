using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace Server.Data
{
    public class DatabaseContext : IdentityDbContext<User, Role, string>
    {
        public DatabaseContext(DbContextOptions options)
            : base(options)
        {
        }
    }
}
