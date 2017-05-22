using System.Reflection;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;
using nscreg.Data.Extensions;
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Data
{
    // ReSharper disable once InconsistentNaming
    public class NSCRegDbContext : IdentityDbContext<User, Role, string>
    {
        public NSCRegDbContext(DbContextOptions options)
            : base(options)
        {
        }

        public DbSet<StatisticalUnit> StatisticalUnits { get; set; }
        public DbSet<LegalUnit> LegalUnits { get; set; }
        public DbSet<EnterpriseUnit> EnterpriseUnits { get; set; }
        public DbSet<LocalUnit> LocalUnits { get; set; }
        public DbSet<EnterpriseGroup> EnterpriseGroups { get; set; }
        public DbSet<Address> Address { get; set; }
        public DbSet<Activity> Activities { get; set; }
        public DbSet<Region> Regions { get; set; }
        public DbSet<ActivityStatisticalUnit> ActivityStatisticalUnits { get; set; }
        public DbSet<ActivityCategory> ActivityCategories { get; set; }
        public DbSet<Soate> Soates { get; set; }
        public DbSet<DataSource> DataSources { get; set; }
        public DbSet<DataSourceQueue> DataSourceQueues { get; set; }
        public DbSet<DataUploadingLog> DataUploadingLogs { get; set; }
        public DbSet<LegalForm> LegalForms { get; set; }
        public DbSet<SectorCode> SectorCodes { get; set; }

        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);
            builder.AddEntityTypeConfigurations(GetType().GetTypeInfo().Assembly);
        }
    }
}
