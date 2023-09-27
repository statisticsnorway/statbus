using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Binding entity with Statistical Unit and Country configuration
    /// </summary>
    public class CountryStatisticalUnitConfiguration : EntityTypeConfigurationBase<CountryForUnit>
    {
        /// <summary>
        /// Statistical unit country configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<CountryForUnit> builder)
        {
            builder.HasKey(v => new { v.LocalUnitId, v.CountryId });
            builder.HasKey(v => new { v.LegalUnitId, v.CountryId });
            builder.HasKey(v => new { v.EnterpriseUnitId, v.CountryId });
            builder.HasOne(v => v.Country).WithMany(v => v.CountriesUnits).HasForeignKey(v => v.CountryId);
            builder.HasOne(v => v.LocalUnit).WithMany(v => v.ForeignParticipationCountriesUnits).HasForeignKey(v => v.LocalUnitId);
            builder.HasOne(v => v.LegalUnit).WithMany(v => v.ForeignParticipationCountriesUnits).HasForeignKey(v => v.LegalUnitId);
            builder.HasOne(v => v.EnterpriseUnit).WithMany(v => v.ForeignParticipationCountriesUnits).HasForeignKey(v => v.EnterpriseUnitId);
        }
    }
}
