using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Entities;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Configuration
{
    public class LegalFormConfiguration : EntityTypeConfigurationBase<LegalForm>
    {
        public override void Configure(EntityTypeBuilder<LegalForm> builder)
        {
            builder.HasKey(x => x.Id);
            builder.Property(x => x.Name).IsRequired();
            builder.Property(x => x.IsDeleted).HasDefaultValue(false);
            builder.HasOne(x=> x.Parent).WithMany(x=> x.LegalForms).HasForeignKey(x=> x.ParentId);
        }
    }
}
