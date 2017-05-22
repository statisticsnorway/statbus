using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class SectorCodesConfiguration : EntityTypeConfigurationBase<SectorCode>
    {
        public override void Configure(EntityTypeBuilder<SectorCode> builder)
        {
            builder.HasKey((x => x.Id));
            builder.HasIndex(x => x.Code).IsUnique();
            builder.Property(x => x.Name).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);
            builder.HasOne(x => x.Parent).WithMany(x => x.SectorCodes).HasForeignKey(x => x.ParentId);
        }
    }
}
