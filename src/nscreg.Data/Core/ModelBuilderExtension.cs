using System;
using System.Linq;
using System.Reflection;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Core.EntityConfiguration;

namespace nscreg.Data.Core
{
    /// <summary>
    /// Класс расширения сборщика модели
    /// </summary>
    public static class ModelBuilderExtension
    {
        /// <summary>
        /// Метод добавления типа сущности конфигурации
        /// </summary>
        /// <param name="builder">Cборщик</param>
        /// <param name="assembly">Сборка</param>
        public static void AddEntityTypeConfigurations(this ModelBuilder builder, Assembly assembly)
        {
            var configurations = assembly.GetTypes()
                .Where(x => !x.GetTypeInfo().IsAbstract)
                .Where(x => x.GetInterfaces()
                    .Any(y => y.GetTypeInfo().IsGenericType &&
                              y.GetGenericTypeDefinition() == typeof(EntityConfiguration.IEntityTypeConfiguration<>)))
                .Select(Activator.CreateInstance)
                .Cast<IEntityTypeConfiguration>();
            foreach (var configuration in configurations)
                configuration.Configure(builder);
        }
    }
}
