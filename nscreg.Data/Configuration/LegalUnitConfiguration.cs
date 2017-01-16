using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class LegalUnitConfiguration : EntityTypeConfigurationBase<LegalUnit>
    {
        public override void Configure(EntityTypeBuilder<LegalUnit> builder)
        {
            builder.HasOne(x => x.EnterpriseUnit).WithMany(x => x.LegalUnits).HasForeignKey(x => x.EnterpriseRegId).IsRequired(false);
        }
    }
}