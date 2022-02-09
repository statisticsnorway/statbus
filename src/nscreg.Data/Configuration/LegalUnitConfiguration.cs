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
            //builder.ToTable("LegalUnits");

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

            builder.Property(x => x.HistoryLocalUnitIds)
                .HasMaxLength(50);

            builder.HasOne(x => x.EnterpriseUnit)
                .WithMany(x => x.LegalUnits)
                .HasForeignKey(x => x.EnterpriseUnitRegId)
                .IsRequired(false);
        }
    }
}
