using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Class configuration activity stat. units
    /// </summary>
    public class ActivityStatisticalUnitConfiguration : EntityTypeConfigurationBase<ActivityStatisticalUnit>
    {
        /// <summary>
        /// Operation configuration method stat. units
        /// </summary>
        public override void Configure(EntityTypeBuilder<ActivityStatisticalUnit> builder)
        {
            builder.HasKey(v => new {v.UnitId, v.ActivityId});
            builder.HasOne(v => v.Activity).WithMany(v => v.ActivitiesUnits).HasForeignKey(v => v.ActivityId);
            builder.HasOne(v => v.Unit).WithMany(v => v.ActivitiesUnits).HasForeignKey(v => v.UnitId);

            builder.HasIndex(x => x.UnitId).IsUnique(false);
            builder.HasIndex(x => x.ActivityId).IsUnique(false);
            
            builder.Property(p => p.ActivityId).HasColumnName("Activity_Id");
            builder.Property(p => p.UnitId).HasColumnName("Unit_Id");
        }
    }
}
