using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Code Sector Configuration Class
    /// </summary>
    public class SectorCodesConfiguration : EntityTypeConfigurationBase<SectorCode>
    {
        /// <summary>
        ///  Code Sector Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<SectorCode> builder)
        {
            builder.HasKey((x => x.Id));
            builder.HasIndex(x => x.Code).IsUnique();
            builder.Property(x => x.Name).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);
            builder.HasOne(x => x.Parent).WithMany(x => x.SectorCodes).HasForeignKey(x => x.ParentId);
        }
    }
}
