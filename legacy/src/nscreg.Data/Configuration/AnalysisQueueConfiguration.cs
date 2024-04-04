
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  Analysis Log Configuration Class
    /// </summary>
    public class AnalysisQueueConfiguration : EntityTypeConfigurationBase<AnalysisQueue>
    {
        /// <summary>
        ///  Analysis Log Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<AnalysisQueue> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.UserId).IsRequired();
            builder.HasOne(x => x.User).WithMany(x => x.AnalysisQueues).HasForeignKey(x => x.UserId);
        }
    }
}
