using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;
using nscreg.Utilities.Extensions;

namespace nscreg.Data.Configuration
{
    public class StatisticalUnitConfiguration : EntityTypeConfigurationBase<StatisticalUnit>
    {
        public override void Configure(EntityTypeBuilder<StatisticalUnit> builder)
        {
            builder.HasKey(x => x.RegId);
            builder.HasOne(x => x.Parrent).WithMany().HasForeignKey(x => x.ParrentId);
            builder.Property(x => x.UserId).IsRequired();
            builder.Property(x => x.ChangeReason).IsNullable();
            builder.Property(x => x.EditComment).IsNullable();
        }
    }
}
