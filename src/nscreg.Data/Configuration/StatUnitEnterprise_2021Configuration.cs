using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class StatUnitEnterprise_2021Configuration : EntityTypeConfigurationBase<StatUnitEnterprise_2021>
    {
        public override void Configure(EntityTypeBuilder<StatUnitEnterprise_2021> builder)
        {
            builder.HasKey(x => x.StatId);
            builder.ToView("V_StatUnitEnterprise_2021");
            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");
        }
    }
}
