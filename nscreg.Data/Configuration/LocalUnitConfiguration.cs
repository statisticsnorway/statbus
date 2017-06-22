using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class LocalUnitConfiguration : EntityTypeConfigurationBase<LocalUnit>
    {
        public override void Configure(EntityTypeBuilder<LocalUnit> builder)
        {
            builder.HasOne(x => x.EnterpriseUnit)
                .WithMany(x => x.LocalUnits)
                .HasForeignKey(x => x.EnterpriseUnitRegId)
                .IsRequired(false);
            builder.HasOne(x => x.LegalUnit)
                .WithMany(x => x.LocalUnits)
                .HasForeignKey(x => x.LegalUnitId)
                .IsRequired(false);
            builder.ToTable("LocalUnits");
        }
    }
}
