using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data;
using nscreg.Utilities.Enums;

namespace nscreg.TestUtils
{
    public static class InMemoryDbSqlite
    {
        public static NSCRegDbContext CreateSqliteDbContext()
        {
            var ctx = new NSCRegDbContext(GetContextOptions());
            ctx.Database.EnsureCreated();

            NscRegDbInitializer.CreateViewsProceduresAndFunctions(ctx, ConnectionProvider.InMemory);

            return ctx;
        }

        private static DbContextOptions<NSCRegDbContext> GetContextOptions()
        {
            var serviceProvider = new ServiceCollection().AddEntityFrameworkSqlite().BuildServiceProvider();
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            var connection = new SqliteConnection("DataSource =:memory:");
            connection.Open();
            builder
                .UseSqlite(connection)
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .UseInternalServiceProvider(serviceProvider);
            return builder.Options;
        }
    }
}
