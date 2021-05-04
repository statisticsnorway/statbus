using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <inheritdoc />
    /// <summary>
    ///  Analysis Log Configuration Class
    /// </summary>
    public class AnalysisLogConfiguration : EntityTypeConfigurationBase<AnalysisLog>
    {
        /// <inheritdoc />
        /// <summary>
        ///  Analysis Log Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<AnalysisLog> builder)
        {
            builder.HasKey(x => x.Id);
            builder.HasOne(x => x.AnalysisQueue).WithMany(x => x.AnalysisLogs).HasForeignKey(x => x.AnalysisQueueId);
            builder.HasIndex(x => new { x.AnalysisQueueId, x.AnalyzedUnitId }).IsUnique(false);
        }
    }
}
