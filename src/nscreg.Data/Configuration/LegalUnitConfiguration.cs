using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;

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
                        builder.HasKey(x => x.RegId);

            builder.Property(v => v.StatId).HasMaxLength(15);
            builder.HasIndex(x => x.StatId);
            builder.Property(x => x.UserId).IsRequired();

            builder.Property(x => x.ChangeReason)
                .IsRequired()
                .HasDefaultValue(ChangeReasons.Create);

            builder.HasOne(x => x.InstSectorCode)
                .WithMany()
                .HasForeignKey(x => x.InstSectorCodeId);

            builder.HasOne(x => x.LegalForm)
                .WithMany()
                .HasForeignKey(x => x.LegalFormId);

            builder.Property(x => x.Name)
                .HasMaxLength(400);

            builder.Property(x => x.ShortName)
                .HasMaxLength(200);

            builder.Property(x => x.TaxRegId)
                .HasMaxLength(50);

            builder.Property(x => x.ExternalId)
                .HasMaxLength(50);

            builder.Property(x => x.ExternalIdType)
                .HasMaxLength(50);

            builder.Property(x => x.DataSource)
                .HasMaxLength(200);

            builder.Property(x => x.WebAddress)
                .HasMaxLength(200);

            builder.Property(x => x.TelephoneNo)
                .HasMaxLength(50);

            builder.Property(x => x.EmailAddress)
                .HasMaxLength(50);

            builder.Property(x => x.LiqReason)
                .HasMaxLength(200);

            builder.Property(x => x.ReorgTypeCode)
                .HasMaxLength(50);

            builder.Property(x => x.UserId)
                .HasMaxLength(100);

            builder.Property(x => x.EditComment)
                .HasMaxLength(500);

            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");

            builder.HasIndex(x => x.Name);

            builder.HasIndex(x => x.StartPeriod);

            builder.HasIndex(nameof(LegalUnit.ShortName),
                nameof(LegalUnit.RegId),
                nameof(LegalUnit.StatId),
                nameof(LegalUnit.TaxRegId));

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

            builder.HasOne(x => x.EnterpriseUnit)
                .WithMany(x => x.LegalUnits)
                .HasForeignKey(x => x.EnterpriseUnitRegId)
                .IsRequired(false);
        }
    }
}
