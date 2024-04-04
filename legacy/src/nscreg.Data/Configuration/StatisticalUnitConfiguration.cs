using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Stat units configuration class
    /// </summary>
    public class StatisticalUnitConfiguration : EntityTypeConfigurationBase<StatisticalUnit>
    {
        private const string DiscriminatorColumnName = "Discriminator";

        /// <summary>
        ///  Stat units configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<StatisticalUnit> builder)
        {
            builder.HasKey(x => x.RegId);

            builder.HasDiscriminator<string>(DiscriminatorColumnName)
            .HasValue<EnterpriseUnit>("EnterpriseUnit")
            .HasValue<LocalUnit>("LocalUnit")
            .HasValue<LegalUnit>("LegalUnit");

            builder.Property(v => v.StatId)
                .HasMaxLength(15);
            builder
                .HasIndex(x => x.StatId);
            builder.Property(x => x.UserId)
                .IsRequired();

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

            builder.Property(DiscriminatorColumnName)
                .HasMaxLength(20);

            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");

            builder.HasIndex(x => x.Name);

            builder.HasIndex(x => x.StartPeriod);

            builder.HasIndex(DiscriminatorColumnName);

            builder.HasIndex(nameof(StatisticalUnit.ShortName),
                nameof(StatisticalUnit.RegId),
                DiscriminatorColumnName,
                nameof(StatisticalUnit.StatId),
                nameof(StatisticalUnit.TaxRegId));
        }
    }
}
