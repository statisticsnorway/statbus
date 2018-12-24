using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Класс конфигурации истории правовой единицы
    /// </summary>
    public class LegalUnitHistoryConfiguration : EntityTypeConfigurationBase<LegalUnitHistory>
    {
        /// <summary>
        ///  Метод конфигурации истории правовой единицы
        /// </summary>
        public override void Configure(EntityTypeBuilder<LegalUnitHistory> builder)
        {
            builder.HasOne(x => x.EnterpriseUnit).WithMany().HasForeignKey(x => x.EnterpriseUnitRegId).IsRequired(false);
            builder.ToTable("LegalUnitsHistory");
        }
    }
}
