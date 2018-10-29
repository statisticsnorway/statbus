using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации источника данных
    /// </summary>
    public class DataSourceConfiguration : EntityTypeConfigurationBase<DataSource>
    {
        /// <summary>
        ///  Метод конфигурации источника данных
        /// </summary>
        public override void Configure(EntityTypeBuilder<DataSource> builder)
        {
            builder.ToTable("DataSourceUploads");
            builder.HasKey(x => x.Id);
            builder.HasIndex(x => x.Name).IsUnique();
            builder.Property(x => x.Name).IsRequired();
            builder.HasOne(x => x.User).WithMany(x => x.DataSources).HasForeignKey(x => x.UserId);
        }
    }
}
