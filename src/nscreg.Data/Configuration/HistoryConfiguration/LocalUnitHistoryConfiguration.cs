using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Local unit history configuration class
    /// </summary>
    public class LocalUnitHistoryConfiguration : EntityTypeConfigurationBase<LocalUnitHistory>
    {
        /// <summary>
        ///  Local Unit History Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<LocalUnitHistory> builder)
        {
            //builder.ToTable("LocalUnitsHistory");
            builder.HasIndex(x => x.LegalUnitId);
        }
    }
}
