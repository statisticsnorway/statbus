using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Класс конфигурации роли видов деятельности
    /// </summary>
    public class ActivityCategoryRoleConfiguration : EntityTypeConfigurationBase<ActivityCategoryRole>
    {
        /// <summary>
        /// Метод конфигурации роли видов деятельности
        /// </summary>
        /// <param name="builder"></param>
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
