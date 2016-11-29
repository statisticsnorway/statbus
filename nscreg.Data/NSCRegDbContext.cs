using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Internal;
using nscreg.Data.Entities;

namespace nscreg.Data
{
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

        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);
            builder.Entity<StatisticalUnit>().HasKey(x => x.RegId);
            builder.Entity<StatisticalUnit>().HasIndex(x => new { x.Name, x.AddressId }).HasName("IX_StatisticalUnits_Name_AddressId").IsUnique();
            builder.Entity<EnterpriseGroup>().HasKey(x => x.RegId);
            builder.Entity<Address>().HasKey(x => x.Id);
            builder.Entity<Address>().HasIndex(x => x.GpsCoordinates).HasName("IX_Address_Unique_GPS").IsUnique();
            builder.Entity<Address>()
                .HasIndex(x => new { x.AddressPart1, x.AddressPart2, x.AddressPart3, x.AddressPart4, x.AddressPart5 })
                .HasName("IX_Address_Unique_AddressParts")
                .IsUnique();
            SetColumnNames(builder);
        }

        private void SetColumnNames(ModelBuilder builder)
        {
            builder.Entity<Address>().Property(p => p.Id).HasColumnName("Address_id");
            builder.Entity<Address>().Property(p => p.AddressPart1).HasColumnName("Address_part1");
            builder.Entity<Address>().Property(p => p.AddressPart2).HasColumnName("Address_part2");
            builder.Entity<Address>().Property(p => p.AddressPart3).HasColumnName("Address_part3");
            builder.Entity<Address>().Property(p => p.AddressPart4).HasColumnName("Address_part4");
            builder.Entity<Address>().Property(p => p.AddressPart5).HasColumnName("Address_part5");
            builder.Entity<Address>().Property(p => p.GeographicalCodes).HasColumnName("Geographical_codes");
            builder.Entity<Address>().Property(p => p.GpsCoordinates).HasColumnName("GPS_coordinates");
        }
    }
}
