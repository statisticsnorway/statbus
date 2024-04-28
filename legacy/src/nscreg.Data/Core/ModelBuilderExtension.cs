using System;
using System.Linq;
using System.Reflection;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Core.EntityConfiguration;

namespace nscreg.Data.Core
{
    /// <summary>
    /// Model Collector Extension Class
    /// </summary>
    public static class ModelBuilderExtension
    {
        /// <summary>
        /// Method for adding a configuration entity type
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
