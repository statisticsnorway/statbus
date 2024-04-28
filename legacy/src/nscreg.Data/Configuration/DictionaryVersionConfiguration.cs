using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class DictionaryVersionConfiguration : EntityTypeConfigurationBase<DictionaryVersion>
    {
        public override void Configure(EntityTypeBuilder<DictionaryVersion> builder)
        {
            builder.HasKey(x => x.Id);
        }
    }
}
