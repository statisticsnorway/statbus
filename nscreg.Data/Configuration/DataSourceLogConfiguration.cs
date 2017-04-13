using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class DataSourceLogConfiguration: EntityTypeConfigurationBase<DataSourceLog>
    {
        public override void Configure(EntityTypeBuilder<DataSourceLog> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.ImportedFile).IsRequired();
            builder.Property(x => x.DataSourceFileName).IsRequired();
            builder.HasOne(x => x.DataSource).WithMany(x => x.DataSourceLogs).HasForeignKey(x => x.DataSourceId);
        }
    }
}
