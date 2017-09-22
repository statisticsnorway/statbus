using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Класс конфигурации ошибок анализа
    /// </summary>
    public class AnalysisErrorConfiguration : EntityTypeConfigurationBase<AnalysisError>
    {
        /// <summary>
        /// Метод конфигурации ошибок анализа
        /// </summary>
        public override void Configure(EntityTypeBuilder<AnalysisError> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.AnalysisLogId).IsRequired();
            builder.HasOne(x => x.AnalysisLog).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.AnalysisLogId);
        }
    }
}
