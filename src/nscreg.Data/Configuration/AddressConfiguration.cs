using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class AddressConfiguration : EntityTypeConfigurationBase<Address>
    {
        public override void Configure(EntityTypeBuilder<Address> builder)
        {
            builder.HasKey(x => x.Id);
            SetColumnNames(builder);
        }

        private static void SetColumnNames(EntityTypeBuilder<Address> builder)
        {
            builder.Property(p => p.Id).HasColumnName("Address_id");
            builder.Property(p => p.AddressPart1).HasColumnName("Address_part1");
            builder.Property(p => p.AddressPart2).HasColumnName("Address_part2");
            builder.Property(p => p.AddressPart3).HasColumnName("Address_part3");
            builder.Property(p => p.RegionId).HasColumnName("Region_id");
            builder.Property(p => p.GpsCoordinates).HasColumnName("GPS_coordinates");
            builder.HasIndex(x => new
            {
                x.AddressPart1,
                x.AddressPart2,
                x.AddressPart3,
                x.RegionId,
                x.GpsCoordinates
            }).IsUnique();
        }
    }
}
