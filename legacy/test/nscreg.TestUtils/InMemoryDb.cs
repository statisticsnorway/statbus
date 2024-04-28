using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.TestUtils
{
    public static class InMemoryDb
    {
        public static NSCRegDbContext CreateDbContext() => new NSCRegDbContext(GetContextOptions());

        public static DbContextOptions<NSCRegDbContext> GetContextOptions()
        {
            ElasticService.ServiceAddress = "http://localhost:9200";
            ElasticService.StatUnitSearchIndexName = "statunitsearchviewtest";
            // The key to keeping the databases unique and not shared is 
            // generating a unique db name for each.
            string dbName = Guid.NewGuid().ToString();

            // Create a fresh service provider, and therefore a fresh 
            // InMemory database instance.
            var serviceProvider = new ServiceCollection()
                .AddEntityFrameworkInMemoryDatabase()
                .BuildServiceProvider();

            // Create a new options instance telling the context to use an
            // InMemory database and the new service provider.
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseInMemoryDatabase(dbName)
                   .UseInternalServiceProvider(serviceProvider);

            return builder.Options;
        }
    }
}
