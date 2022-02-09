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
            //var serviceProvider = new ServiceCollection().AddEntityFrameworkInMemoryDatabase().BuildServiceProvider();
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
#pragma warning disable CS0618 // Type or member is obsolete
            builder
                //.UseInMemoryDatabase()
#pragma warning restore CS0618 // Type or member is obsolete
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning));
                //.UseInternalServiceProvider(serviceProvider);
            return builder.Options;
        }
    }
}
