using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class EnterpriseGroupConfiguration : EntityTypeConfigurationBase<EnterpriseGroup>
    {
        public override void Configure(EntityTypeBuilder<EnterpriseGroup> builder)
        {
            builder.HasMany(x => x.EnterpriseUnits).WithOne(x => x.EnterpriseGroup).HasForeignKey(x => x.EntGroupId).IsRequired(false);
            builder.HasOne(x => x.Parrent).WithMany().HasForeignKey(x => x.ParrentId);
        }
    }
}