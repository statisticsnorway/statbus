using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class SampleFrameConfiguration : EntityTypeConfigurationBase<SampleFrame>
    {
        public override void Configure(EntityTypeBuilder<SampleFrame> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Name).IsRequired();
            builder.Property(x => x.Description);
            builder.Property(x => x.Predicate).IsRequired();
            builder.Property(x => x.Fields).IsRequired();
            builder.Property(x => x.CreationDate).IsRequired();
            builder.Property(x => x.EditingDate);
            builder.HasOne(x => x.User).WithMany(x => x.SampleFrames).HasForeignKey(x => x.UserId);
        }
    }
}
