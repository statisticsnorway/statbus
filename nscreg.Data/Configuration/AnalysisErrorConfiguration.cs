using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class AnalysisErrorConfiguration : EntityTypeConfigurationBase<AnalysisError>
    {
        public override void Configure(EntityTypeBuilder<AnalysisError> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.AnalysisLogId).IsRequired();
            builder.HasOne(x => x.AnalysisLog).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.AnalysisLogId);
        }
    }

    public class AnalysisStatisticalErrorConfiguration : EntityTypeConfigurationBase<AnalysisStatisticalError>
    {
        public override void Configure(EntityTypeBuilder<AnalysisStatisticalError> builder)
        {
            builder.Property(x => x.StatisticalRegId).IsRequired();
            builder.HasOne(x => x.StatisticalUnit).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.StatisticalRegId);
        }
    }

    public class AnalysisGroupErrorConfiguration : EntityTypeConfigurationBase<AnalysisGroupError>
    {
        public override void Configure(EntityTypeBuilder<AnalysisGroupError> builder)
        {
            builder.Property(x => x.GroupRegId).IsRequired();
            builder.HasOne(x => x.EnterpriseGroup).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.GroupRegId);
        }
    }
}
