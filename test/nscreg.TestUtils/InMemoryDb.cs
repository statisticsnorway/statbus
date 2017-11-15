using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data;

namespace nscreg.TestUtils
{
    public static class InMemoryDb
    {
        public static NSCRegDbContext CreateDbContext() => new NSCRegDbContext(GetContextOptions());

        private static DbContextOptions<NSCRegDbContext> GetContextOptions()
        {
            var serviceProvider = new ServiceCollection().AddEntityFrameworkInMemoryDatabase().BuildServiceProvider();
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder
                .UseInMemoryDatabase()
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .UseInternalServiceProvider(serviceProvider);
            return builder.Options;
        }
    }
}
