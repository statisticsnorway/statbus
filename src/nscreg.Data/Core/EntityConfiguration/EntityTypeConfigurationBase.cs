using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace nscreg.Data.Core.EntityConfiguration
{
    public abstract class EntityTypeConfigurationBase<T> : IEntityTypeConfiguration<T> where T : class
    {
        public void Configure(ModelBuilder builder)
        {
            Configure(builder.Entity<T>());
        }

        public abstract void Configure(EntityTypeBuilder<T> builder);
    }
}
