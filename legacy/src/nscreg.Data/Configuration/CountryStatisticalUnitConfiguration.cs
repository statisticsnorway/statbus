using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Binding entity with Statistical Unit and Country configuration
    /// </summary>
    public class CountryStatisticalUnitConfiguration : EntityTypeConfigurationBase<CountryStatisticalUnit>
    {
        /// <summary>
        /// Statistical unit country configuration method
        /// </summary>
        public override void Configure(EntityTypeBuilder<CountryStatisticalUnit> builder)
        {
            builder.HasKey(v => new { v.UnitId, v.CountryId });
            builder.HasOne(v => v.Country).WithMany(v => v.CountriesUnits).HasForeignKey(v => v.CountryId);
            builder.HasOne(v => v.Unit).WithMany(v => v.ForeignParticipationCountriesUnits).HasForeignKey(v => v.UnitId);

            builder.Property(p => p.CountryId).HasColumnName("Country_Id");
            builder.Property(p => p.UnitId).HasColumnName("Unit_Id");
        }
    }
}
