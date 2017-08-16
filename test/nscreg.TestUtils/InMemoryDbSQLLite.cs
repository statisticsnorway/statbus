using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data;

namespace nscreg.TestUtils
{
    public static class InMemoryDbSqlLite
    {
        public static NSCRegDbContext CreateSlqLiteDbContext()
        {
            var ctx = new NSCRegDbContext(GetContextOptions());
            ctx.Database.EnsureCreated();
            return ctx;
        }

        private static DbContextOptions<NSCRegDbContext> GetContextOptions()
        {
            var serviceProvider = new ServiceCollection().AddEntityFrameworkSqlite().BuildServiceProvider();
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            var connection = new SqliteConnection("DataSource=:memory:");
            connection.Open();
            builder
                .UseSqlite(connection)
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .UseInternalServiceProvider(serviceProvider);
            return builder.Options;
        }
    }
}
