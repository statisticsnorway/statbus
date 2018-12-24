using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Класс конфигурации персоны стат. единицы
    /// </summary>
    public class PersonStatisticalUnitHistoryConfiguration : EntityTypeConfigurationBase<PersonStatisticalUnitHistory>
    {
        public override void Configure(EntityTypeBuilder<PersonStatisticalUnitHistory> builder)
        {
            builder.HasKey(v => new { v.UnitId, v.PersonId });
            builder.HasOne(v => v.Person).WithMany().HasForeignKey(v => v.PersonId);
            builder.HasOne(v => v.Unit).WithMany(v => v.PersonsUnits).HasForeignKey(v => v.UnitId);
            builder.HasOne(v => v.StatUnit).WithMany().HasForeignKey(v => v.StatUnitId);

            builder.Property(p => p.PersonId).HasColumnName("Person_Id");
            builder.Property(p => p.UnitId).HasColumnName("Unit_Id");
            builder.Property(p => p.StatUnitId).HasColumnName("StatUnit_Id");
            builder.Property(p => p.EnterpriseGroupId).HasColumnName("GroupUnit_Id");

            builder.HasIndex(x => new { x.PersonType, x.UnitId, x.PersonId }).IsUnique();
        }
    }
}
