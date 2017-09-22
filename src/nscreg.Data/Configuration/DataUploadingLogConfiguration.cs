using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации журнала загрузки данных
    /// </summary>
    public class DataUploadingLogConfiguration: EntityTypeConfigurationBase<DataUploadingLog>
    {
        /// <summary>
        ///  Метод конфигурации журнала загрузки данных
        /// </summary>
        public override void Configure(EntityTypeBuilder<DataUploadingLog> builder)
        {
            builder.HasKey(x => x.Id);
            builder.HasOne(x => x.DataSourceQueue)
                .WithMany(x => x.DataUploadingLogs)
                .HasForeignKey(x => x.DataSourceQueueId);
        }
    }
}
