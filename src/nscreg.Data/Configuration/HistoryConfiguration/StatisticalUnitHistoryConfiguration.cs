using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Statistical units configuration class
    /// </summary>
    public class StatisticalUnitHistoryConfiguration : EntityTypeConfigurationBase<StatisticalUnitHistory>
    {
        /// <summary>
        ///  Statistical unit history configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<StatisticalUnitHistory> builder)
        {
            builder.HasKey(x => x.RegId);
            builder.HasOne(x => x.Parent).WithMany().HasForeignKey(x => x.ParentId);
            builder.Property(v => v.StatId).HasMaxLength(15);
            builder.HasIndex(x => x.StatId);
            builder.Property(x => x.UserId).IsRequired();
            builder.Property(x => x.ChangeReason).IsRequired().HasDefaultValue(ChangeReasons.Create);
            builder.HasOne(x => x.InstSectorCode).WithMany().HasForeignKey(x => x.InstSectorCodeId);
            builder.HasOne(x => x.LegalForm).WithMany().HasForeignKey(x => x.LegalFormId);
            builder.Property(x => x.Name).HasMaxLength(400);
            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");
            builder.HasIndex(x => x.Name);
            builder.HasIndex(x => x.StartPeriod);
            builder.HasIndex(x => new { x.StatId, x.EndPeriod }).IsUnique(false);
        }
    }
}
