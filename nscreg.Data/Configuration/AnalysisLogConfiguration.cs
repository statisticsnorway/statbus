using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class AnalysisLogConfiguration : EntityTypeConfigurationBase<AnalysisLog>
    {
        public override void Configure(EntityTypeBuilder<AnalysisLog> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.UserId).IsRequired();
            builder.HasOne(x => x.User).WithMany(x => x.AnalysisLogs).HasForeignKey(x => x.UserId);
        }
    }
}
