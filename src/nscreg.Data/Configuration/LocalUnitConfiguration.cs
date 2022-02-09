using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Local Unit Configuration Class
    /// </summary>
    public class LocalUnitConfiguration : EntityTypeConfigurationBase<LocalUnit>
    {
        /// <summary>
        ///  Local Unit Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<LocalUnit> builder)
        {
            builder.HasOne(x => x.LegalUnit)
                .WithMany(x => x.LocalUnits)
                .HasForeignKey(x => x.LegalUnitId)
                .IsRequired(false);
            //builder.ToTable("LocalUnits");
        }
    }
}
