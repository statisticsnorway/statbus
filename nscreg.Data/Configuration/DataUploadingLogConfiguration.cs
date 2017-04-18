using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class DataUploadingLogConfiguration: EntityTypeConfigurationBase<DataUploadingLog>
    {
        public override void Configure(EntityTypeBuilder<DataUploadingLog> builder)
        {
            builder.HasKey(x => x.Id);
            builder.HasOne(x => x.DataSourceQueue)
                .WithMany(x => x.DataUploadingLogs)
                .HasForeignKey(x => x.DataSourceQueueId);
        }
    }
}
