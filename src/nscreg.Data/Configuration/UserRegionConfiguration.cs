using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    ///  User Region Configuration Class
    /// </summary>
    public class UserRegionConfiguration : EntityTypeConfigurationBase<UserRegion>
    {
        /// <summary>
        ///  User Region Configuration Method
        /// </summary>
        public override void Configure(EntityTypeBuilder<UserRegion> builder)
        {
            builder.HasKey(x => new {x.UserId, x.RegionId});
            builder.HasOne(x => x.User).WithMany(x => x.UserRegions).HasForeignKey(x => x.UserId);
            builder.HasOne(x => x.Region).WithMany(x => x.UserRegions).HasForeignKey(x => x.RegionId);

            builder.Property(x => x.UserId).HasColumnName("User_Id");
            builder.Property(x => x.RegionId).HasColumnName("Region_Id");
        }
    }
}
