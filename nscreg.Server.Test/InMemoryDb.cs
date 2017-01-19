using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data;

namespace nscreg.Server.Test
{
    public class InMemoryDb
    {
        private static DbContextOptions<NSCRegDbContext> GetContextOptions()
        {
            var serviceProvider = new ServiceCollection().AddEntityFrameworkInMemoryDatabase().BuildServiceProvider();
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseInMemoryDatabase().UseInternalServiceProvider(serviceProvider);
            return builder.Options;
        }

        public static NSCRegDbContext CreateContext() => new NSCRegDbContext(GetContextOptions());
    }
}