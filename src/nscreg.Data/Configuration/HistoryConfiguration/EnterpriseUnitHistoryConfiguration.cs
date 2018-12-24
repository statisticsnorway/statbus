using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Класс конфигурации истории предприятия
    /// </summary>
    public class EnterpriseUnitHistoryConfiguration : EntityTypeConfigurationBase<EnterpriseUnitHistory>
    {
        /// <summary>
        ///  Метод конфигурации истории предприятия
        /// </summary>
        public override void Configure(EntityTypeBuilder<EnterpriseUnitHistory> builder)
        {
            builder.HasOne(x => x.EnterpriseGroup).WithMany(x => x.EnterpriseUnits).HasForeignKey(x => x.EntGroupId).IsRequired(false);
            builder.ToTable("EnterpriseUnitsHistory");
        }
    }
}
