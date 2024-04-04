using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Binding entity with Statistical Unit and Country configuration
    /// </summary>
    public class CountryStatisticalUnitHistoryConfiguration : EntityTypeConfigurationBase<CountryStatisticalUnitHistory>
    {
        /// <summary>
        /// Operation configuration method stat. units
        /// </summary>
        public override void Configure(EntityTypeBuilder<CountryStatisticalUnitHistory> builder)
        {
            builder.HasKey(v => new { v.UnitId, v.CountryId });
            builder.HasOne(v => v.Country).WithMany().HasForeignKey(v => v.CountryId);
            builder.HasOne(v => v.Unit).WithMany(v => v.ForeignParticipationCountriesUnits).HasForeignKey(v => v.UnitId);

            builder.Property(p => p.CountryId).HasColumnName("Country_Id");
            builder.Property(p => p.UnitId).HasColumnName("Unit_Id");
        }
    }
}
