using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class StatisticalUnitReportingViewConfiguration : EntityTypeConfigurationBase<StatisticalUnitReportingView>
    {
        public override void Configure(EntityTypeBuilder<StatisticalUnitReportingView> builder)
        {
            builder.HasKey(x => x.Id);
            builder.HasOne(x=> x.StatisticalUnit).WithMany(x=> x.ReportingViews).HasForeignKey(x => x.StatId);
            builder.HasOne(x=> x.ReportingView).WithMany(x=> x.StatisticalUnits).HasForeignKey(x => x.RepViewId);
        }
    }

}



