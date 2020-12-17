using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    /// Class configuration history of activity stat. units
    /// </summary>
    public class ActivityStatisticalUnitHistoryConfiguration : EntityTypeConfigurationBase<ActivityStatisticalUnitHistory>
    {
        /// <summary>
        /// Operation configuration method stat. units
        /// </summary>
        public override void Configure(EntityTypeBuilder<ActivityStatisticalUnitHistory> builder)
        {
            builder.HasKey(v => new { v.UnitId, v.ActivityId });
            builder.HasOne(v => v.Activity).WithMany(x => x.ActivitiesUnits).HasForeignKey(v => v.ActivityId);
            builder.HasOne(v => v.Unit).WithMany(v => v.ActivitiesUnits).HasForeignKey(v => v.UnitId);
            
            builder.Property(p => p.ActivityId).HasColumnName("Activity_Id");
            builder.Property(p => p.UnitId).HasColumnName("Unit_Id");
        }
    }
}
