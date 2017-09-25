using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации журнала анализа
    /// </summary>
    public class AnalysisLogConfiguration : EntityTypeConfigurationBase<AnalysisLog>
    {
        /// <summary>
        ///  Метод конфигурации журнала анализа
        /// </summary>
        public override void Configure(EntityTypeBuilder<AnalysisLog> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.UserId).IsRequired();
            builder.HasOne(x => x.User).WithMany(x => x.AnalysisLogs).HasForeignKey(x => x.UserId);
        }
    }
}
