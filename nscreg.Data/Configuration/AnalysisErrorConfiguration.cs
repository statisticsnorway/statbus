using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class AnalysisErrorConfiguration : EntityTypeConfigurationBase<AnalysisError>
    {
        public override void Configure(EntityTypeBuilder<AnalysisError> builder)
        {
            builder.HasKey(x => x.AnalysisLogId);
            builder.Property(x => x.AnalysisLogId).IsRequired();
            builder.Property(x => x.RegId).IsRequired();
            builder.HasOne(x => x.AnalysisLog).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.AnalysisLogId);
            builder.HasOne(x => x.StatisticalUnit).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.RegId);
        }
    }
}
