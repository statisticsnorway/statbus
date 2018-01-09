using System;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Enums;

namespace nscreg.Data
{
    /// <summary>
    /// Класс конфигурации контекста БД
    /// </summary>
    public static class DbContextHelper
    {
        public static NSCRegDbContext Create(ConnectionSettings config)
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            switch (config.ParseProvider())
            {
                case ConnectionProvider.SqlServer:
                    return new NSCRegDbContext(builder
                        .UseSqlServer(config.ConnectionString)
                        .ConfigureWarnings(x => x.Throw(RelationalEventId.QueryClientEvaluationWarning))
                        .Options);
                case ConnectionProvider.PostgreSql:
                    return new NSCRegDbContext(builder
                        .UseNpgsql(config.ConnectionString)
                        .ConfigureWarnings(x => x.Throw(RelationalEventId.QueryClientEvaluationWarning))
                        .Options);
                default:
                    var ctx = new NSCRegDbContext(builder
                        .UseSqlite("DataSource=:memory:")
                        .ConfigureWarnings(x => x.Throw(RelationalEventId.QueryClientEvaluationWarning))
                        .Options);
                    ctx.Database.OpenConnection();
                    ctx.Database.EnsureCreated();
                    return ctx;
            }
        }

        /// <summary>
        /// Метод конфигурации контекста БД
        /// </summary>
        public static readonly Func<IConfiguration, Action<DbContextOptionsBuilder>> ConfigureOptions =
            config =>
                op =>
                {
                    var connectionSettings = config.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
                    switch (connectionSettings.ParseProvider())
                    {
                        case ConnectionProvider.SqlServer:
                            op.UseSqlServer(connectionSettings.ConnectionString,
                                op2 => op2.MigrationsAssembly("nscreg.Data"));
                            break;
                        case ConnectionProvider.PostgreSql:
                            op.UseNpgsql(connectionSettings.ConnectionString,
                                op2 => op2.MigrationsAssembly("nscreg.Data"));
                            break;
                        default:
                            op.UseSqlite(new SqliteConnection("DataSource=:memory:"));
                            break;
                    }
                };
    }
}
