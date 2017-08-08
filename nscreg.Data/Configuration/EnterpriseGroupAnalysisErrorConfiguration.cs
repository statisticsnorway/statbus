using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class EnterpriseGroupAnalysisErrorConfiguration : EntityTypeConfigurationBase<EnterpriseGroupAnalysisError>
    {
        public override void Configure(EntityTypeBuilder<EnterpriseGroupAnalysisError> builder)
        {
            builder.Property(x => x.GroupRegId).IsRequired();
            builder.HasOne(x => x.EnterpriseGroup).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.GroupRegId);
        }
    }
}
