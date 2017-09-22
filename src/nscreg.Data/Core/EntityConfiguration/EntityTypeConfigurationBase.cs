using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace nscreg.Data.Core.EntityConfiguration
{
    /// <summary>
    /// Класс конфигурации типов сущности
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public abstract class EntityTypeConfigurationBase<T> : IEntityTypeConfiguration<T> where T : class
    {
        public void Configure(ModelBuilder builder)
        {
            Configure(builder.Entity<T>());
        }

        /// <summary>
        /// Метод конфигурации типов сущности
        /// </summary>
        /// <param name="builder"></param>
        public abstract void Configure(EntityTypeBuilder<T> builder);
    }
}
