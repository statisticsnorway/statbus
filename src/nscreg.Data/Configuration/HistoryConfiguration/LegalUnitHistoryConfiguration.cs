using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Legal unit history configuration class
    /// </summary>
    public class LegalUnitHistoryConfiguration : EntityTypeConfigurationBase<LegalUnitHistory>
    {
        /// <summary>
        ///  Legal unit history configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<LegalUnitHistory> builder)
        {
            //builder.ToTable("LegalUnitsHistory");
            builder.HasIndex(x => x.EnterpriseUnitRegId);
        }
    }
}
