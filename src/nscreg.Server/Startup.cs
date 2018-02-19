using System;
using FluentValidation.AspNetCore;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
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
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.Localization;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using System.IO;
using nscreg.Utilities.Enums;
using static nscreg.Server.Core.StartupConfiguration;

namespace nscreg.Server
{
    /// <summary>
    /// Класс запуска приложения
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
                    Path.Combine(env.ContentRootPath, "..", "..", "appsettings.Shared.json"),
                    true);
            }

            builder
                .AddJsonFile("appsettings.Shared.json", true)
                .AddJsonFile("appsettings.json", true)
                .AddJsonFile($"appsettings.{env.EnvironmentName}.json", true)
                .AddEnvironmentVariables();

            if (env.IsDevelopment()) builder.AddUserSecrets<Startup>();

            Configuration = builder.Build();
            CurrentEnvironment = env;
        }

        /// <summary>
        /// Метод конфигурации приложения
        /// </summary>
        /// <param name="app">Приложение</param>
        /// <param name="loggerFactory">Журнал записи</param>
        // ReSharper disable once UnusedMember.Global
        public void Configure(IApplicationBuilder app, ILoggerFactory loggerFactory)
        {
            loggerFactory
                .AddConsole(Configuration.GetSection("Logging"))
                .AddDebug()
                .AddNLog();

            _loggerFactory = loggerFactory;

            app.UseStaticFiles();

            app.UseIdentity()
                .UseMvc(routes => routes.MapRoute(
                    "default",
                    "{*url}",
                    new {controller = "Home", action = "Index"}));

            var provider = Configuration
                .GetSection(nameof(ConnectionSettings))
                .Get<ConnectionSettings>()
                .ParseProvider();

            var reportingSettingsProvider = Configuration
                .GetSection(nameof(ReportingSettings))
                .Get<ReportingSettings>();

            var dbContext = app.ApplicationServices.GetService<NSCRegDbContext>();
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
            if (CurrentEnvironment.IsStaging()) NscRegDbInitializer.RecreateDb(dbContext);
            NscRegDbInitializer.CreateStatUnitSearchViewAndGetReportsTreeProcedure(
                dbContext, provider, reportingSettingsProvider);
            NscRegDbInitializer.EnsureRoles(dbContext);
            if (provider == ConnectionProvider.InMemory) NscRegDbInitializer.Seed(dbContext);
        }

        /// <summary>
        /// Метод конфигуратор сервисов
        /// </summary>
        /// <param name="services">Сервисы</param>
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
                .AddAntiforgery(op => op.CookieName = op.HeaderName = "X-XSRF-TOKEN")
                .AddDbContext<NSCRegDbContext>(DbContextHelper.ConfigureOptions(Configuration))
                .AddIdentity<User, Role>(ConfigureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();
            services
                .AddScoped<IAuthorizationHandler, SystemFunctionAuthHandler>()
                .AddScoped<IUserService, UserService>();
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
                .AddViews();
        }

        /// <summary>
        /// Метод запуска приложения
        /// </summary>
        public static void Main() => new WebHostBuilder()
            .UseKestrel(options =>
            {
                options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(20);
            })
            .UseContentRoot(Directory.GetCurrentDirectory())
            .UseIISIntegration()
            .UseStartup<Startup>()
            .Build()
            .Run();
    }
}
