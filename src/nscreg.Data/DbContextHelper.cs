using System;
using System.IO;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Enums;

namespace nscreg.Data
{
    /// <summary>
    /// DB Context Configuration Class
    /// </summary>
    public class DbContextHelper: IDesignTimeDbContextFactory<NSCRegDbContext>
    {
        public DbContextHelper(){}
        /// <summary>
        /// DB context configuration method
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
                                op2 => op2.MigrationsAssembly("nscreg.Data").CommandTimeout(300));
                            break;
                        case ConnectionProvider.PostgreSql:
                            op.UseNpgsql(connectionSettings.ConnectionString,
                                op2 => op2.MigrationsAssembly("nscreg.Data").CommandTimeout(300));
                            break;
                        case ConnectionProvider.MySql:
                            op.UseMySql(connectionSettings.ConnectionString,
                                op2 => op2.MigrationsAssembly("nscreg.Data").CommandTimeout(300));
                            break;
                        default:
                            op.UseSqlite(new SqliteConnection("DataSource=:memory:"));
                            break;
                    }
                };

        public NSCRegDbContext CreateDbContext(string[] args)
        {
            var configBuilder = new ConfigurationBuilder();
            var baseDirectory = AppContext.BaseDirectory;
            configBuilder
                .SetBasePath(baseDirectory)
                .AddJsonFile(Path.Combine(baseDirectory, "appsettings.Shared.json"), true);

            var configuration = configBuilder.Build();
            var config = configuration.GetSection(nameof(ConnectionSettings))
                .Get<ConnectionSettings>();

            return Create(config);
        }

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
                case ConnectionProvider.MySql:
                    return new NSCRegDbContext(builder.UseMySql(config.ConnectionString)
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
    }
}
