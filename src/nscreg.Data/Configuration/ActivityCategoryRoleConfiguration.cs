using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class ActivityCategoryRoleConfiguration : EntityTypeConfigurationBase<ActivityCategoryRole>
    {
        public override void Configure(EntityTypeBuilder<ActivityCategoryRole> builder)
        {
            builder.HasKey(x => new { x.RoleId, x.ActivityCategoryId });
            builder.HasOne(x => x.Role).WithMany(x => x.ActivitysCategoryRoles).HasForeignKey(x => x.RoleId);
            builder.HasOne(x => x.ActivityCategory).WithMany(x => x.ActivityCategoryRoles)
                .HasForeignKey(x => x.ActivityCategoryId);

            builder.Property(x => x.RoleId).HasColumnName("Role_Id");
            builder.Property(x => x.ActivityCategoryId).HasColumnName("Activity_Category_Id");
        }
    }
}
