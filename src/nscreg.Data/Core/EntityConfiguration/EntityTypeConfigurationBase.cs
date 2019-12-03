using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace nscreg.Data.Core.EntityConfiguration
{
    /// <summary>
    /// Entity Type Configuration Class
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public abstract class EntityTypeConfigurationBase<T> : IEntityTypeConfiguration<T> where T : class
    {
        public void Configure(ModelBuilder builder)
        {
            Configure(builder.Entity<T>());
        }

        /// <summary>
        /// Entity Type Configuration Method
        /// </summary>
        /// <param name="builder"></param>
        public abstract void Configure(EntityTypeBuilder<T> builder);
    }
}
