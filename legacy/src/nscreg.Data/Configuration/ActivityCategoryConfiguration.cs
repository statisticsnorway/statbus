using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class ActivityCategoryConfiguration : EntityTypeConfigurationBase<ActivityCategory>
    {
        public override void Configure(EntityTypeBuilder<ActivityCategory> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Name).IsRequired();
            builder.HasIndex(x => x.Code).IsUnique();
            builder.Property(v => v.Code).IsRequired().HasMaxLength(10);
            builder.Property(v => v.Section).HasMaxLength(10).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);

            builder.HasOne(v => v.Parent).WithMany(v => v.Children).HasForeignKey(v => v.ParentId);
        }
    }
}
