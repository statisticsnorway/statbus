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
            //builder.ToTable("EnterpriseUnits");

            builder.Property(x => x.TotalCapital)
                .HasMaxLength(100);

            builder.Property(x => x.MunCapitalShare)
                .HasMaxLength(100);

            builder.Property(x => x.StateCapitalShare)
                .HasMaxLength(100);

            builder.Property(x => x.PrivCapitalShare)
                .HasMaxLength(100);

            builder.Property(x => x.ForeignCapitalShare)
                .HasMaxLength(100);

            builder.Property(x => x.ForeignCapitalCurrency)
                .HasMaxLength(100);


            builder.HasOne(x => x.EnterpriseGroup)
                .WithMany(x => x.EnterpriseUnits)
                .HasForeignKey(x => x.EntGroupId)
                .IsRequired(false);

            builder.HasMany(x => x.LegalUnits)
                .WithOne(x => x.EnterpriseUnit)
                .HasForeignKey(x => x.EnterpriseUnitRegId)
                .IsRequired(false);

            builder.HasOne(c => c.EntGroupRole)
                .WithMany(c => c.EnterpriseUnits)
                .HasForeignKey(c => c.EntGroupRoleId)
                .IsRequired(false);

        }
    }
}
