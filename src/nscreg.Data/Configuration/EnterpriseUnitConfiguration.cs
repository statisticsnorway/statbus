using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Enterprise Configuration Class
    /// </summary>
    public class EnterpriseUnitConfiguration : EntityTypeConfigurationBase<EnterpriseUnit>
    {
        /// <summary>
        ///  Enterprise Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<EnterpriseUnit> builder)
        {
            builder.HasOne(x => x.EnterpriseGroup).WithMany(x => x.EnterpriseUnits).HasForeignKey(x => x.EntGroupId).IsRequired(false);
            builder.HasMany(x => x.LegalUnits).WithOne(x => x.EnterpriseUnit).HasForeignKey(x => x.EnterpriseUnitRegId).IsRequired(false);
            builder.ToTable("EnterpriseUnits");
            builder.HasOne(c => c.EntGroupRole).WithMany(c => c.EnterpriseUnits).HasForeignKey(c => c.EntGroupRoleId)
                .IsRequired(false);
        }
    }
}
