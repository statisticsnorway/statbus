using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace Server.Data
{
    public class DatabaseContext : IdentityDbContext<User>
    {
        public DatabaseContext(DbContextOptions options)
            : base(options)
        {
        }

        public new DbSet<User> Users { get; set; }
        public new DbSet<Role> Roles { get; set; }
    }
}
