
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации журнала анализа
    /// </summary>
    public class AnalysisQueueConfiguration : EntityTypeConfigurationBase<AnalysisQueue>
    {
        /// <summary>
        ///  Метод конфигурации журнала анализа
        /// </summary>
        public override void Configure(EntityTypeBuilder<AnalysisQueue> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.UserId).IsRequired();
            builder.HasOne(x => x.User).WithMany(x => x.AnalysisQueues).HasForeignKey(x => x.UserId);
        }
    }
}
