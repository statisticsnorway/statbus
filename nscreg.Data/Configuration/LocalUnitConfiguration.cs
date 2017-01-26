using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class LocalUnitConfiguration : EntityTypeConfigurationBase<LocalUnit>
    {
        public override void Configure(EntityTypeBuilder<LocalUnit> builder)
        {
            builder.HasOne(x => x.EnterpriseUnit).WithMany(x => x.LocalUnits).HasForeignKey(x => x.EnterpriseUnitRegId).IsRequired(false);
            builder.ToTable("LocalUnits");
        }
    }
}