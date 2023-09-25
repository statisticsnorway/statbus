using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class ActivityCategoryUserConfiguration : EntityTypeConfigurationBase<ActivityCategoryUser>
    {
        public override void Configure(EntityTypeBuilder<ActivityCategoryUser> builder)
        {
            builder.HasKey(x => new {x.UserId, x.ActivityCategoryId});
            builder.HasOne(x => x.User).WithMany(x => x.ActivityCategoryUsers).HasForeignKey(x => x.UserId);
            builder.HasOne(x => x.ActivityCategory).WithMany(x => x.ActivityCategoryUsers).HasForeignKey(x => x.ActivityCategoryId);

            builder.Property(p => p.UserId).HasColumnName("User_Id");
            builder.Property(p => p.ActivityCategoryId).HasColumnName("ActivityCategory_Id");
        }
    }
}
