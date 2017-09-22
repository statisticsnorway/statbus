using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации правовой формы собственности
    /// </summary>
    public class LegalFormConfiguration : EntityTypeConfigurationBase<LegalForm>
    {
        /// <summary>
        ///  Метод конфигурации правовой формы собственности
        /// </summary>
        public override void Configure(EntityTypeBuilder<LegalForm> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Name).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);
            builder.HasOne(x=> x.Parent).WithMany(x=> x.LegalForms).HasForeignKey(x=> x.ParentId);
        }
    }
}
