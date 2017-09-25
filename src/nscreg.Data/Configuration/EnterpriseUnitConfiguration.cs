using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации предприятия
    /// </summary>
    public class EnterpriseUnitConfiguration : EntityTypeConfigurationBase<EnterpriseUnit>
    {
        /// <summary>
        ///  Метод конфигурации предприятия
        /// </summary>
        public override void Configure(EntityTypeBuilder<EnterpriseUnit> builder)
        {
            builder.HasOne(x => x.EnterpriseGroup).WithMany(x => x.EnterpriseUnits).HasForeignKey(x => x.EntGroupId).IsRequired(false);
            builder.HasMany(x => x.LegalUnits).WithOne(x => x.EnterpriseUnit).HasForeignKey(x => x.EnterpriseUnitRegId).IsRequired(false);
            builder.ToTable("EnterpriseUnits");
        }
    }
}
