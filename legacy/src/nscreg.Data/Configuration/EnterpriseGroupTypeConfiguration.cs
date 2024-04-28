using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class EnterpriseGroupTypeConfiguration : EntityTypeConfigurationBase<EnterpriseGroupType>
    {
        public override void Configure(EntityTypeBuilder<EnterpriseGroupType> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Name).IsRequired();
            builder.HasIndex(x => x.Code).IsUnique();
            builder.Property(x => x.Code).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);
        }
    }
}
