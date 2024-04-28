using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    public class PersonsConfiguration : EntityTypeConfigurationBase<Person>
    {
        public override void Configure(EntityTypeBuilder<Person> builder)
        {
            builder.HasIndex(x => new { x.GivenName, x.Surname });
            builder.Ignore(x => x.Role);
        }
    }
}
