using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;

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

            builder.HasIndex(nameof(StatisticalUnit.ShortName),
                nameof(StatisticalUnit.RegId),
                nameof(StatisticalUnit.StatId),
                nameof(StatisticalUnit.TaxRegId));


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
