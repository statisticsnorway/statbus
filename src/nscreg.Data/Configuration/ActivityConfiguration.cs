using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Activity configuration class
    /// </summary>
    public class ActivityConfiguration : EntityTypeConfigurationBase<Activity>
    {
        /// <summary>
        /// Activity configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<Activity> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(v => v.UpdatedBy).IsRequired();
            builder.HasOne(v => v.UpdatedByUser).WithMany().HasForeignKey(v => v.UpdatedBy);
            builder.HasOne(v => v.ActivityCategory).WithMany().HasForeignKey(v => v.ActivityCategoryId);
            SetColumnNames(builder);
        }

        /// <summary>
        /// Column Name Setting Method
        /// </summary>
        private static void SetColumnNames(EntityTypeBuilder<Activity> builder)
        {
            builder.Property(p => p.Turnover).HasColumnType("decimal(18,2)");
        }
    }
}
