using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;

namespace nscreg.Data
{
    public class NSCRegDbContext : IdentityDbContext<User, Role, string>
    {
        public NSCRegDbContext(DbContextOptions options)
            : base(options)
        {
        }
        
        public DbSet<LegalUnit> LegalUnits { get; set; }
        public DbSet<EnterpriseUnit> EnterpriseUnits { get; set; }
        public DbSet<LocalUnit> LocalUnits { get; set; }
        public DbSet<EnterpriseGroup> EnterpriseGroups { get; set; }

    }
}
