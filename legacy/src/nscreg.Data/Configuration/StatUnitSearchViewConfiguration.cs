using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class StatUnitSearchViewConfiguration : EntityTypeConfigurationBase<StatUnitSearchView>
    {
        public override void Configure(EntityTypeBuilder<StatUnitSearchView> builder)
        {
            builder.HasKey(x => x.RegId);
            builder.ToView("V_StatUnitSearch");
            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");
        }
    }
}
