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
    public class DbContextHelper : IDesignTimeDbContextFactory<NSCRegDbContext>
    {
        private IConfiguration _configuration;

        public DbContextHelper(IConfiguration configuration)
        {
            _configuration = configuration;
        }

        // Used by `dotnet ef` commands to get the database context.
        public DbContextHelper()
        {
            var configBuilder = new ConfigurationBuilder();
            var baseDirectory = AppContext.BaseDirectory;
            var appsettingsSharedPath = Path.Combine(
                baseDirectory,
                "..", "..","..","..","..",
                "appsettings.Shared.json");

            configBuilder
                .SetBasePath(baseDirectory)
                .AddJsonFile(appsettingsSharedPath, true);

            _configuration = configBuilder.Build();
        }

        /// <summary>
        /// DB context configuration method
        /// </summary>
        public static readonly Func<IConfiguration, Action<DbContextOptionsBuilder>> ConfigureOptions =
            config =>
                op =>
                {
                    var connectionSettings = config.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
                    var connectionString = connectionSettings.ConnectionString;
                    switch (connectionSettings.ParseProvider())
                    {
                        case ConnectionProvider.SqlServer:
                            op.UseSqlServer(connectionString,
                                op2 => op2.MigrationsAssembly("nscreg.Data")
                                    .CommandTimeout(30000));
                            break;
                        case ConnectionProvider.PostgreSql:
                            op.UseNpgsql(connectionString,
                                op2 => op2.MigrationsAssembly("nscreg.Data")
                                    .CommandTimeout(30000));
                            break;
                        case ConnectionProvider.MySql:
                            op.UseMySql(connectionString: connectionString,
                                MariaDbServerVersion.LatestSupportedServerVersion,
                                op2 => op2.MigrationsAssembly("nscreg.Data")
                                    .CommandTimeout(30000));
                            break;
                        default:
                            op.UseSqlite(new SqliteConnection("DataSource=:memory:"));
                            break;
                    }

                    // Change from a warning about a potential N+1 load problem,
                    // to an exception, that pinpoints the source code where the
                    // problem happened.
                    op.ConfigureWarnings(w => w.Throw(RelationalEventId.MultipleCollectionIncludeWarning));
                    // Provide more information from EF upon errors,
                    // to make it possible to identify where the problem lies.
                    op.EnableDetailedErrors();
                    op.EnableSensitiveDataLogging();
                };

        public NSCRegDbContext CreateDbContext(string[] args)
        {
            var config = _configuration.GetSection(nameof(ConnectionSettings))
                .Get<ConnectionSettings>();

            return Create(config);
        }

        public static NSCRegDbContext Create(ConnectionSettings config)
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            var defaultCommandTimeOutInSeconds = (int) TimeSpan.FromHours(24).TotalSeconds;
            switch (config.ParseProvider())
            {
                case ConnectionProvider.SqlServer:
                    return new NSCRegDbContext(builder
                        .UseSqlServer(config.ConnectionString, options => { options.CommandTimeout(defaultCommandTimeOutInSeconds); })
                        .Options);
                case ConnectionProvider.PostgreSql:
                    return new NSCRegDbContext(builder
                        .UseNpgsql(config.ConnectionString, options => { options.CommandTimeout(defaultCommandTimeOutInSeconds); })
                        .Options);
                case ConnectionProvider.MySql:
                    return new NSCRegDbContext(builder
                        .UseMySql(config.ConnectionString, MariaDbServerVersion.LatestSupportedServerVersion, options => { options.CommandTimeout(defaultCommandTimeOutInSeconds); })
                        .Options);
                default:
                    var ctx = new NSCRegDbContext(builder
                        .UseSqlite("DataSource=:memory:")
                        .Options);
                    ctx.Database.OpenConnection();
                    ctx.Database.EnsureCreated();
                    return ctx;
            }
        }
    }
}
