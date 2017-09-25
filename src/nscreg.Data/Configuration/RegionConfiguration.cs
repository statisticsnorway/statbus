using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации региона
    /// </summary>
    public class RegionConfiguration : EntityTypeConfigurationBase<Region>
    {
        /// <summary>
        ///  Метод конфигурации региона
        /// </summary>
        public override void Configure(EntityTypeBuilder<Region> builder)
        {
            builder.HasKey(x => x.Id);
            builder.HasIndex(x => x.Code).IsUnique();
            builder.Property(x => x.Name).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);
        }
    }
}
