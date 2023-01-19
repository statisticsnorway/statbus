using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class StatUnitLocal_2021Configuration : EntityTypeConfigurationBase<StatUnitLocal_2021>
    {
        public override void Configure(EntityTypeBuilder<StatUnitLocal_2021> builder)
        {
            builder.HasKey(x => x.StatId);
            builder.ToView("V_StatUnitLocal_2021");
            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");
        }
    }
}
