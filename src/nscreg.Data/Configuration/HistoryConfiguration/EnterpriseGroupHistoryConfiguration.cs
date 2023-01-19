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
            builder.Property(x => x.Turnover).HasColumnType("decimal(18,2)");
            builder.HasIndex(x => x.Name);
            builder.HasIndex(x => x.StartPeriod);
            builder.HasOne(c => c.ReorgType).WithMany(z => z.EnterpriseGroupHistories).HasForeignKey(z => z.ReorgTypeId).IsRequired(false);
            builder.HasOne(c => c.UnitStatus).WithMany(z => z.EnterpriseGroupHistories).HasForeignKey(z => z.UnitStatusId).IsRequired(false);
            builder.HasOne(c => c.Type).WithMany(z => z.EnterpriseGroupsHistories).HasForeignKey(z => z.EntGroupTypeId).IsRequired(false);

            builder.Ignore(x => x.LegalFormId);
            builder.Ignore(x => x.LegalForm);
            builder.Ignore(x => x.InstSectorCode);
            builder.Ignore(x => x.InstSectorCodeId);
        }
    }
}
