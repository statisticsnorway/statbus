using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class StatisticalUnitAnalysisErrorConfiguration : EntityTypeConfigurationBase<StatisticalUnitAnalysisError>
    {
        public override void Configure(EntityTypeBuilder<StatisticalUnitAnalysisError> builder)
        {
            builder.Property(x => x.StatisticalRegId).IsRequired();
            builder.HasOne(x => x.StatisticalUnit).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.StatisticalRegId);
        }
    }
}
