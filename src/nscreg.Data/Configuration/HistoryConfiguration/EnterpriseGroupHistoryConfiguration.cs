using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities.History;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;

namespace nscreg.Data.Configuration.HistoryConfiguration
{
    /// <summary>
    ///  Enterprise Group Configuration Class
    /// </summary>
    public class EnterpriseGroupHistoryConfiguration : EntityTypeConfigurationBase<EnterpriseGroupHistory>
    {
        public override void Configure(EntityTypeBuilder<EnterpriseGroupHistory> builder)
        {
            builder.HasKey(x => x.RegId);
            builder.ToTable("EnterpriseGroupsHistory");
            builder.Property(x => x.UserId).IsRequired();
            builder.Property(x => x.ChangeReason).IsRequired().HasDefaultValue(ChangeReasons.Create);
            builder.Property(x => x.EditComment).IsNullable();
            builder.Property(x => x.Name).HasMaxLength(400);
            builder.HasIndex(x => x.Name);
            builder.HasIndex(x => x.StartPeriod);

            builder.Ignore(x => x.LegalForm);
            builder.Ignore(x => x.InstSectorCode);
        }
    }
}
