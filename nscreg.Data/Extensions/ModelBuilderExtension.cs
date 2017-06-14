using System;
using System.Linq;
using System.Reflection;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Infrastructure.EntityConfiguration;

namespace nscreg.Data.Extensions
{
    public static class ModelBuilderExtension
    {
        public static void AddEntityTypeConfigurations(this ModelBuilder builder, Assembly assembly)
        {
            var configurations = assembly.GetTypes()
                .Where(x => !x.GetTypeInfo().IsAbstract)
                .Where(x => x.GetInterfaces()
                    .Any(y => y.GetTypeInfo().IsGenericType &&
                              y.GetGenericTypeDefinition() == typeof(IEntityTypeConfiguration<>)))
                .Select(Activator.CreateInstance)
                .Cast<IEntityTypeConfiguration>();
            foreach (var configuration in configurations)
                configuration.Configure(builder);
        }
    }
}
