using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Legal Unit Configuration Class
    /// </summary>
    public class LegalUnitConfiguration : EntityTypeConfigurationBase<LegalUnit>
    {
        /// <summary>
        ///  Legal Unit Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<LegalUnit> builder)
        {
            builder.HasOne(x => x.EnterpriseUnit).WithMany(x => x.LegalUnits).HasForeignKey(x => x.EnterpriseUnitRegId).IsRequired(false);
            builder.ToTable("LegalUnits");
        }
    }
}
