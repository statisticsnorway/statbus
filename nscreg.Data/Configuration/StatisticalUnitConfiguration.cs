using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Configuration
{
    public class StatisticalUnitConfiguration : EntityTypeConfigurationBase<StatisticalUnit>
    {
        public override void Configure(EntityTypeBuilder<StatisticalUnit> builder)
        {
            builder.HasKey(x => x.RegId);
            builder.HasOne(x => x.Parrent).WithMany().HasForeignKey(x => x.ParrentId);
            builder.Property(v => v.StatId).HasMaxLength(15);
            builder.HasIndex(x => x.StatId);
            builder.Property(x => x.UserId).IsRequired();
            builder.Property(x => x.ChangeReason).IsRequired().HasDefaultValue(ChangeReasons.Create);
        }
    }
}
