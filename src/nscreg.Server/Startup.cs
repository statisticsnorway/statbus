using FluentValidation.AspNetCore;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Localization;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.Localization;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.Data.Common;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using Npgsql;
using static nscreg.Server.Core.StartupConfiguration;
using Microsoft.Extensions.Hosting;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Common.Helpers;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.AspNetCore.Mvc.ViewFeatures;
using Microsoft.AspNetCore.DataProtection;
using MySqlConnector;
using Newtonsoft.Json.Serialization;
using nscreg.Server.HostedServices;
using nscreg.Services;
using nscreg.Server.Common.Services.SampleFrames;

namespace nscreg.Server
{
    /// <summary>
    /// Application Launch Class
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Startup
    {
        private IConfiguration Configuration { get; }
        private ILoggerFactory _loggerFactory;
        private IWebHostEnvironment CurrentEnvironment { get; set; }

        public Startup(IConfiguration configuration, IWebHostEnvironment environment)
        {
            Configuration = configuration;
            CurrentEnvironment = environment;
        }

        /// <summary>
        /// Application Configuration Method
        /// </summary>
        /// <param name="app">App</param>
        /// <param name="loggerFactory">loggerFactory</param>
        // ReSharper disable once UnusedMember.Global
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env, ILoggerFactory loggerFactory)
        {

            var builder = new ConfigurationBuilder().SetBasePath(env.ContentRootPath);

            if (env.IsDevelopment())
            {
                builder.AddJsonFile(
                    Path.Combine(env.ContentRootPath, "..", "..", "appsettings.json"),
                    true);
            }

            builder
                .AddJsonFile("appsettings.json", true, reloadOnChange: true)
                .AddJsonFile(path: $"appsettings.{env.EnvironmentName}.json", optional: true, reloadOnChange: true)
                .AddEnvironmentVariables();

            _loggerFactory = loggerFactory;

            var localization = Configuration.GetSection(nameof(LocalizationSettings));
            Localization.LanguagePrimary = localization["DefaultKey"];
            Localization.Language1 = localization["Language1"];
            Localization.Language2 = localization["Language2"];
            Localization.Initialize();
            var supportedCultures = new List<CultureInfo>(new[]
                {new CultureInfo(Localization.LanguagePrimary), new CultureInfo(Localization.Language1), new CultureInfo(Localization.Language2)});
            app.UseRequestLocalization(new RequestLocalizationOptions()
            {
                DefaultRequestCulture = new RequestCulture(Localization.LanguagePrimary),
                SupportedCultures = supportedCultures,
                SupportedUICultures = supportedCultures
            });
            app.UseHttpsRedirection();
            app.UseStaticFiles();
            app.UseRouting();
            app.UseAuthentication();
            app.UseAuthorization();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapHealthChecks("/healthz").RequireAuthorization();
                endpoints.MapControllerRoute(
                    name: "default",
                    pattern: "{*url}",
                    new { controller = "Home", action = "Index" });
                endpoints.MapRazorPages();
            });

            var provider = Configuration
                .GetSection(nameof(ConnectionSettings))
                .Get<ConnectionSettings>()
                .ParseProvider();

            var reportingSettingsProvider = Configuration
                .GetSection(nameof(ReportingSettings))
                .Get<ReportingSettings>();

            using (var serviceScope = app.ApplicationServices.CreateScope())
            {
                var dbContext = serviceScope.ServiceProvider.GetService<NSCRegDbContext>();
                if (provider == ConnectionProvider.InMemory)
                {
                    dbContext.Database.OpenConnection();
                    dbContext.Database.EnsureCreated();
                }
                else
                {
                    dbContext.Database.SetCommandTimeout(600);
                    dbContext.Database.Migrate();
                    EvolveMigrate();
                }

                if (env.IsStaging()) { NscRegDbInitializer.RecreateDb(dbContext); }
                if (provider == ConnectionProvider.InMemory) { NscRegDbInitializer.Seed(dbContext); }
                NscRegDbInitializer.CreateViewsProceduresAndFunctions(
                    dbContext, provider, reportingSettingsProvider);
                NscRegDbInitializer.EnsureRoles(dbContext);
                NscRegDbInitializer.EnsureEntGroupTypes(dbContext);
                NscRegDbInitializer.EnsureEntGroupRoles(dbContext);
            }

            ElasticService.ServiceAddress = Configuration["ElasticServiceAddress"];
            ElasticService.StatUnitSearchIndexName = Configuration["ElasticStatUnitSearchIndexName"];

        }


        private const string MsSqlEvolveMigrationScriptsFolderName = "MsSql";
        private const string PostgreSqlEvolveMigrationScriptsFolderName = "PostgreSql";
        private const string MySqlEvolveMigrationScriptsFolderName = "MySql";
        private void EvolveMigrate()
        {
            var connectionSettings = Configuration.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
            var connectionString = connectionSettings.ConnectionString;
            DbConnection connection;

            string migrationFolderName;
            switch (connectionSettings.ParseProvider())
            {
                case ConnectionProvider.SqlServer:
                    migrationFolderName = MsSqlEvolveMigrationScriptsFolderName;
                    connection = new SqlConnection(connectionString);
                    break;
                case ConnectionProvider.PostgreSql:
                    migrationFolderName = PostgreSqlEvolveMigrationScriptsFolderName;
                    connection = new NpgsqlConnection(connectionString);
                    break;
                case ConnectionProvider.MySql:
                    migrationFolderName = MySqlEvolveMigrationScriptsFolderName;
                    connection = new MySqlConnection(connectionString);
                    break;
                default:
                    throw new Exception( "Invalid connection provider");
            }
            var evolve = new EvolveDb.Evolve(connection, Console.WriteLine)
            {
                Locations = new[] {$"EvolveMigrations/{migrationFolderName}"},
                IsEraseDisabled = true,
                CommandTimeout = null
            };
            evolve.Migrate();
        }


        /// <summary>
        /// Service Configurator Method
        /// </summary>
        /// <param name="services">Services</param>
        // ReSharper disable once UnusedMember.Global
        public void ConfigureServices(IServiceCollection services)
        {
            services.Configure<DbMandatoryFields>(x => Configuration.GetSection(nameof(DbMandatoryFields)).Bind(x));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<DbMandatoryFields>>().Value);
            services.Configure<LocalizationSettings>(x =>
                Configuration.GetSection(nameof(LocalizationSettings)).Bind(x));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<LocalizationSettings>>().Value);
            services.Configure<StatUnitAnalysisRules>(x =>
                Configuration.GetSection(nameof(StatUnitAnalysisRules)).Bind(x));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<StatUnitAnalysisRules>>().Value);
            services.Configure<ServicesSettings>(x => Configuration.GetSection(nameof(ServicesSettings)).Bind(x));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<ServicesSettings>>().Value);
            services.Configure<ReportingSettings>(x => Configuration.GetSection(nameof(ReportingSettings)).Bind(x));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<ReportingSettings>>().Value);
            services.Configure<ValidationSettings>(Configuration.GetSection(nameof(ValidationSettings)));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<ValidationSettings>>().Value);
            services
                .AddAntiforgery(op => op.Cookie.Name = op.HeaderName = "X-XSRF-TOKEN")
                .AddDbContext<NSCRegDbContext>(DbContextHelper.ConfigureOptions(Configuration))
                .AddIdentity<User, Role>(ConfigureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();

            var keysDirectory = Path.Combine(CurrentEnvironment.ContentRootPath, Configuration.GetValue<string>("DataProtectionKeysDir") ?? "keys");
            if (!Directory.Exists(keysDirectory))
                Directory.CreateDirectory(keysDirectory);

            services.AddLogging(loggingBuilder =>
            {
                loggingBuilder.AddConfiguration(Configuration.GetSection("Logging"));
                loggingBuilder.AddConsole();
                loggingBuilder.AddDebug();
            });

            services
                .AddDataProtection()
                .PersistKeysToFileSystem(new DirectoryInfo(keysDirectory))
                .SetApplicationName("nscreg")
                .SetDefaultKeyLifetime(TimeSpan.FromDays(7));

            services
                .AddScoped<IAuthorizationHandler, SystemFunctionAuthHandler>()
                .AddScoped<IUserService, UserService>()
                .AddScoped(typeof( UserManager <User>));
            services.AddTransient<AnalysisQueueService>();
            services.AddTransient<DataSourcesQueueService>();
            services.AddTransient<DataSourcesService>();
            services.AddTransient<LookupService>();
            services.AddTransient<PersonService>();
            services.AddTransient<RegionService>();
            services.AddTransient<ReportService>();
            services.AddTransient<RoleService>();
            services.AddTransient<CommonService>();
            services.AddTransient<IAddressService, AddressService>();
            services.AddTransient<IElasticUpsertService, ElasticService>();
            services.AddTransient<IStatUnitAnalyzeService, AnalyzeService>();
            services.AddTransient<CreateService>();
            services.AddTransient<DataAccessService>();
            services.AddTransient<EditService>();
            services.AddTransient<DeleteService>();
            services.AddTransient<LinkService>();
            services.AddTransient<SearchService>();
            services.AddTransient<ViewService>();
            services.AddTransient<HistoryService>();
            services.AddTransient<StatUnitAnalysisHelper>();
            services.AddTransient<StatUnitCheckPermissionsHelper>();
            services.AddTransient<StatUnitCreationHelper>();

            services.AddTransient<SampleFrameExecutor>();
            services.AddTransient<FileGenerationWorker>();
            services.AddTransient<AnalyseWorker>();
            services.AddTransient<DataUploadSvcWorker>();

            services.AddHostedService<SampleFrameGenerationHostedService>();
            services.AddHostedService<AnalysisHostedService>();
            services.AddHostedService<DataUploadSvcHostedService>();
            services.AddHostedService<DataUploadSvcQueueCleanupHostedService>();

            services
                .AddMvcCore(op =>
                {
                    op.Filters.Add(
                        new AuthorizeFilter(
                            new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build()));
                    op.Filters.Add(new ValidateModelStateAttribute());
                })
                .AddMvcOptions(op => op.Filters.Add(new GlobalExceptionFilter(_loggerFactory)))
                .AddFluentValidation(op => op.RegisterValidatorsFromAssemblyContaining<IStatUnitM>())
                .AddAuthorization(options => options.AddPolicy(
                    nameof(SystemFunctions),
                    policyBuilder => { policyBuilder.Requirements.Add(new SystemFunctionAuthRequirement()); }))
                .AddNewtonsoftJson(options =>
                    {
                        options.SerializerSettings.ContractResolver = new CamelCasePropertyNamesContractResolver();
                    }
                )
                .AddRazorViewEngine()
                .AddDataAnnotationsLocalization()
                .AddViewLocalization()
                .AddViews();
            services.AddHealthChecks();
            services.AddCors();
            services.AddRazorPages();
            services.AddAutoMapper(typeof(AutoMapperProfile).Assembly);
            services.AddControllersWithViews();
        }

        public static void Main(string[] args)
        {
            CreateWebHostBuilder(args)
                .Build()
                .Run();
        }

        public static IWebHostBuilder CreateWebHostBuilder(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
                .UseContentRoot(Directory.GetCurrentDirectory())
                //.UseIISIntegration()
                .UseStartup<Startup>()
                .ConfigureKestrel((context, options) =>
                {
                    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(1); //20
                    options.Limits.MaxRequestBodySize = long.MaxValue;
                });
    }
}
