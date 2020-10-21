using FluentValidation.AspNetCore;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Localization;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Newtonsoft.Json.Serialization;
using NLog.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.Localization;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using static nscreg.Server.Core.StartupConfiguration;
using IHostingEnvironment = Microsoft.AspNetCore.Hosting.IHostingEnvironment;

namespace nscreg.Server
{
    /// <summary>
    /// Application Launch Class
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Startup
    {
        private IConfiguration Configuration { get; }
        private IHostingEnvironment CurrentEnvironment { get; }
        private ILoggerFactory _loggerFactory;

        public Startup(IHostingEnvironment env)
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

            Configuration = builder.Build();
            CurrentEnvironment = env;
        }

        /// <summary>
        /// Application Configuration Method
        /// </summary>
        /// <param name="app">App</param>
        /// <param name="loggerFactory">loggerFactory</param>
        // ReSharper disable once UnusedMember.Global
        public void Configure(IApplicationBuilder app, ILoggerFactory loggerFactory)
        {
#pragma warning disable CS0618 // Type or member is obsolete
            loggerFactory
                .AddConsole(Configuration.GetSection("Logging"))
                .AddDebug()
                .AddNLog();
#pragma warning restore CS0618 // Type or member is obsolete

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
            app.UseStaticFiles();
#pragma warning disable CS0618 // Type or member is obsolete
            app.UseIdentity()
#pragma warning restore CS0618 // Type or member is obsolete
                .UseMvc(routes => routes.MapRoute(
                    "default",
                    "{*url}",
                    new { controller = "Home", action = "Index" }));

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
                }

                if (CurrentEnvironment.IsStaging()) {NscRegDbInitializer.RecreateDb(dbContext);}
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

        /// <summary>
        /// Service Configurator Method
        /// </summary>
        /// <param name="services">Services</param>
        // ReSharper disable once UnusedMember.Global
        public void ConfigureServices(IServiceCollection services)
        {
            ConfigureAutoMapper();
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
            services
                .AddScoped<IAuthorizationHandler, SystemFunctionAuthHandler>()
                .AddScoped<IUserService, UserService>();
            services.AddTransient(config => Configuration);
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
                .AddJsonFormatters(op => op.ContractResolver = new CamelCasePropertyNamesContractResolver())
                .AddRazorViewEngine()
                .AddDataAnnotationsLocalization()
                .AddViewLocalization()
                .AddViews();

            var keysDirectory = new DirectoryInfo(Configuration["DataProtectionKeysDir"]);
            if (!keysDirectory.Exists)
                keysDirectory.Create();

            services.AddDataProtection()
                .PersistKeysToFileSystem(keysDirectory)
                .SetApplicationName("nscreg")
                .SetDefaultKeyLifetime(TimeSpan.FromDays(7));
        }

        /// <summary>
        /// Application Launch Method
        /// </summary>
        public static void Main()
        {
            try
            {
                CreateWebHostBuilder().UseKestrel(options =>
                    {
                        options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(1); //20
                    })
                    .UseContentRoot(Directory.GetCurrentDirectory())
                    .UseIISIntegration()
                    .UseKestrel(options => options.Limits.MaxRequestBodySize = long.MaxValue)
                    .UseStartup<Startup>()
                    .Build().Run();
            }
            catch (Exception ex)
            {
                var logger = NLog.LogManager.GetCurrentClassLogger();
                logger.Error(ex);
            }
        }
        public static IWebHostBuilder CreateWebHostBuilder() =>
            WebHost.CreateDefaultBuilder()
                .UseStartup<Startup>();
    }
}
