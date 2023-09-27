using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Person configuration class stat. units
    /// </summary>
    public class PersonStatisticalUnitConfiguration : EntityTypeConfigurationBase<PersonForUnit>
    {
        public override void Configure(EntityTypeBuilder<PersonForUnit> builder)
        {
            builder.HasKey(v => new { v.LocalUnitId, v.PersonId});
            builder.HasKey(v => new { v.LegalUnitId, v.PersonId});
            builder.HasKey(v => new { v.EnterpriseUnitId, v.PersonId});
            builder.HasOne(v => v.Person).WithMany(v => v.PersonsUnits).HasForeignKey(v => v.PersonId);
            builder.HasOne(v => v.LocalUnit).WithMany(v => v.PersonsUnits).HasForeignKey(v => v.LocalUnitId);
            builder.HasOne(v => v.LegalUnit).WithMany(v => v.PersonsUnits).HasForeignKey(v => v.LegalUnitId);
            builder.HasOne(v => v.EnterpriseUnit).WithMany(v => v.PersonsUnits).HasForeignKey(v => v.EnterpriseUnitId);

            builder.Property(p => p.PersonId);
            builder.Property(p => p.LocalUnitId);
            builder.Property(p => p.LegalUnitId);
            builder.Property(p => p.EnterpriseUnitId);
            builder.Property(p => p.EnterpriseGroupId);

            builder.HasIndex(x => new {
                x.PersonTypeId,
                x.LocalUnitId,
                x.LegalUnitId,
                x.EnterpriseUnitId,
                x.PersonId}).IsUnique();
            builder.HasIndex(x => x.LocalUnitId).IsUnique(false);
            builder.HasIndex(x => x.LegalUnitId).IsUnique(false);
            builder.HasIndex(x => x.EnterpriseUnitId).IsUnique(false);
        }
    }
}
