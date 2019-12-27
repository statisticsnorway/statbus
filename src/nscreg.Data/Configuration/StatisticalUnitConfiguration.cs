using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Stat units configuration class 
    /// </summary>
    public class StatisticalUnitConfiguration : EntityTypeConfigurationBase<StatisticalUnit>
    {
        /// <summary>
        ///  Stat units configuration method 
        /// </summary>
        public override void Configure(EntityTypeBuilder<StatisticalUnit> builder)
        {
            builder.HasKey(x => x.RegId);
            builder.Property(v => v.StatId).HasMaxLength(15);
            builder.HasIndex(x => x.StatId);
            builder.Property(x => x.UserId).IsRequired();
            builder.Property(x => x.ChangeReason).IsRequired().HasDefaultValue(ChangeReasons.Create);
            builder.HasOne(x => x.InstSectorCode).WithMany().HasForeignKey(x => x.InstSectorCodeId);
            builder.HasOne(x => x.LegalForm).WithMany().HasForeignKey(x => x.LegalFormId);
            builder.Property(x => x.Name).HasMaxLength(400);
            builder.HasIndex(x => x.Name);
            builder.HasIndex(x => x.StartPeriod);
        }
    }
}
