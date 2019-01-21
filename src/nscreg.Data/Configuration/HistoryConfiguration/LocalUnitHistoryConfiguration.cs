using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Класс конфигурации истории местной единицы
    /// </summary>
    public class LocalUnitHistoryConfiguration : EntityTypeConfigurationBase<LocalUnitHistory>
    {
        /// <summary>
        ///  Метод конфигурации истории местной единицы
        /// </summary>
        public override void Configure(EntityTypeBuilder<LocalUnitHistory> builder)
        {
            builder.ToTable("LocalUnitsHistory");
            builder.HasIndex(x => x.LegalUnitId);
        }
    }
}
