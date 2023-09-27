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
    public class StatisticalUnitConfiguration : EntityTypeConfigurationBase<History>
    {
        private const string DiscriminatorColumnName = "Discriminator";

        /// <summary>
        ///  Stat units configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<History> builder)
        {
            builder.Property(x => x.UserId).IsRequired();

            builder.Property(x => x.ChangeReason)
                .IsRequired()
                .HasDefaultValue(ChangeReasons.Create);

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

            builder.Property(x => x.UserId)
                .HasMaxLength(100);

            builder.Property(x => x.EditComment)
                .HasMaxLength(500);

            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");

            builder.HasIndex(x => x.Name);
        }
    }
}
