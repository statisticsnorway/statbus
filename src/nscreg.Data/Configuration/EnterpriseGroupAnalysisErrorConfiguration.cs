using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации ошибок анализа группы предприятия
    /// </summary>
    public class EnterpriseGroupAnalysisErrorConfiguration : EntityTypeConfigurationBase<EnterpriseGroupAnalysisError>
    {
        /// <summary>
        ///  Метод конфигурации ошибок анализа групп предприятий
        /// </summary>
        public override void Configure(EntityTypeBuilder<EnterpriseGroupAnalysisError> builder)
        {
            builder.Property(x => x.GroupRegId).IsRequired();
            builder.HasOne(x => x.EnterpriseGroup).WithMany(x => x.AnalysisErrors).HasForeignKey(x => x.GroupRegId);
        }
    }
}
