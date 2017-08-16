using FluentValidation.AspNetCore;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Serialization;
using NLog.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using System.IO;
using Microsoft.Extensions.Options;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Utilities;
using static nscreg.Server.Core.StartupConfiguration;

// ReSharper disable UnusedMember.Global

namespace nscreg.Server
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Startup
    {
        private IConfiguration Configuration { get; }
        private IHostingEnvironment CurrentEnvironment { get; }
        private ILoggerFactory _loggerFactory;

        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile(Directory.GetParent(Directory.GetCurrentDirectory()).FullName + "\\appsettings.json", true, true)
                .AddJsonFile("appsettings.json", true, true)
                .AddJsonFile($"appsettings.{env.EnvironmentName}.json", true)
                .AddEnvironmentVariables();

            if (env.IsDevelopment()) builder.AddUserSecrets<Startup>();

            Configuration = builder.Build();
            CurrentEnvironment = env;
        }

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

            var dbContext = app.ApplicationServices.GetService<NSCRegDbContext>();
            if (CurrentEnvironment.IsStaging()) NscRegDbInitializer.RecreateDb(dbContext);
            NscRegDbInitializer.Seed(dbContext);
        }

        public void ConfigureServices(IServiceCollection services)
        {
            ConfigureAutoMapper();
            services.Configure<CommonSettings>(x => Configuration.GetSection(nameof(CommonSettings)).Bind(x));
            services.AddScoped(cfg => cfg.GetService<IOptionsSnapshot<CommonSettings>>().Value);
            services
                .AddAntiforgery(op => op.CookieName = op.HeaderName = "X-XSRF-TOKEN")
                .AddDbContext<NSCRegDbContext>(ConfigureDbContext(Configuration))
                .AddIdentity<User, Role>(ConfigureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();

            services
                .AddScoped<IAuthorizationHandler, SystemFunctionAuthHandler>()
                .AddScoped<IUserService, UserService>();

            services
                .AddMvcCore(op =>
                {
                    op.Filters.Add(new AuthorizeFilter(
                        new AuthorizationPolicyBuilder()
                            .RequireAuthenticatedUser()
                            .Build()));
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

        public static void Main() => new WebHostBuilder()
            .UseKestrel()
            .UseContentRoot(Directory.GetCurrentDirectory())
            .UseIISIntegration()
            .UseStartup<Startup>()
            .Build()
            .Run();
    }
}
