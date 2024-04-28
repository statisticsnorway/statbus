using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class CustomAnalysisCheckConfiguration : EntityTypeConfigurationBase<CustomAnalysisCheck>
    {
        public override void Configure(EntityTypeBuilder<CustomAnalysisCheck> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Name).HasMaxLength(64);
            builder.Property(x => x.Query).HasMaxLength(2048);
            builder.Property(x => x.TargetUnitTypes).HasMaxLength(16);
        }
    }
}
