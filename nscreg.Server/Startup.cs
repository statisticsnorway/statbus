using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Serialization;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Core;
using System;
using System.IO;
using System.Threading.Tasks;
using nscreg.Server.Models;
using FluentValidation.AspNetCore;
// ReSharper disable UnusedMember.Global

namespace nscreg.Server
{
    public class Startup
    {
        private IConfiguration Configuration { get; }
        private IHostingEnvironment CurrentEnvironment { get; }
        private ILoggerFactory _loggerFactory;

        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile("appsettings.json", true, true)
                .AddJsonFile($"appsettings.{env.EnvironmentName}.json", true)
                .AddEnvironmentVariables();

            if (env.IsDevelopment()) builder.AddUserSecrets();

            Configuration = builder.Build();
            CurrentEnvironment = env;
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
        {
            loggerFactory
                .AddConsole(Configuration.GetSection("Logging"))
                .AddDebug();

            _loggerFactory = loggerFactory;

            app.UseStaticFiles();

            app.UseIdentity()
                .UseMvc(routes => routes.MapRoute(
                    "default",
                    "{*url}",
                    new {controller = "Home", action = "Index"}));

            if (env.IsDevelopment())
                NscRegDbInitializer.Seed(app.ApplicationServices.GetService<NSCRegDbContext>());
        }

        public void ConfigureServices(IServiceCollection services)
        {
            AutoMapperConfiguration.Configure();

            services
                .AddAntiforgery(op => op.CookieName = op.HeaderName = "X-XSRF-TOKEN")
                .AddDbContext<NSCRegDbContext>(_configureDbContext(Configuration))
                .AddIdentity<User, Role>(_configureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();

            services
                .AddMvcCore(op =>
                {
                    op.Filters.Add(new AuthorizeFilter(
                        new AuthorizationPolicyBuilder()
                            .RequireAuthenticatedUser()
                            .Build()));
                    op.Filters.Add(new ValidateModelStateAttribute());
                })
                .AddMvcOptions(op =>
                {
                    if (!CurrentEnvironment.IsDevelopment())
                        op.Filters.Add(new GlobalExceptionFilter(_loggerFactory));
                })
                .AddFluentValidation(op =>
                    op.RegisterValidatorsFromAssemblyContaining<Startup>())
                .AddAuthorization()
                .AddJsonFormatters(op =>
                    op.ContractResolver = new CamelCasePropertyNamesContractResolver())
                .AddRazorViewEngine()
                .AddViews();
        }

        public static void Main()
        {
            new WebHostBuilder()
                .UseKestrel()
                .UseContentRoot(Directory.GetCurrentDirectory())
                .UseIISIntegration()
                .UseStartup<Startup>()
                .Build()
                .Run();
        }

        #region CONFIGURATIONS

        private readonly Func<IConfiguration, Action<DbContextOptionsBuilder>> _configureDbContext =
            config =>
                op =>
                {
                    var useInMemoryDb = config.GetValue<bool>("UseInMemoryDatabase");
                    if (useInMemoryDb)
                        op.UseInMemoryDatabase();
                    else
                        op.UseNpgsql(
                            config.GetConnectionString("DefaultConnection"),
                            op2 => op2.MigrationsAssembly("nscreg.Data"));
                };

        private readonly Action<IdentityOptions> _configureIdentity =
            op =>
            {
                op.Password.RequiredLength = 6;
                op.Password.RequireDigit = false;
                op.Password.RequireNonAlphanumeric = false;
                op.Password.RequireLowercase = false;
                op.Password.RequireUppercase = false;

                op.Cookies.ApplicationCookie.CookieHttpOnly = true;
                op.Cookies.ApplicationCookie.ExpireTimeSpan = TimeSpan.FromDays(7);
                op.Cookies.ApplicationCookie.LoginPath = "/account/login";
                op.Cookies.ApplicationCookie.LogoutPath = "/account/logout";
                op.Cookies.ApplicationCookie.Events = new CookieAuthenticationEvents
                {
                    OnRedirectToLogin = ctx =>
                    {
                        if (ctx.Request.Path.StartsWithSegments("/api") && ctx.Response.StatusCode == 200)
                            ctx.Response.StatusCode = 401;
                        else
                            ctx.Response.Redirect(ctx.RedirectUri);
                        return Task.FromResult(0);
                    }
                    //OnRedirectToLogin = ctx =>
                    //{
                    //    if (!ctx.Request.Path.StartsWithSegments("/api"))
                    //        ctx.Response.Redirect(ctx.RedirectUri);
                    //    else if (ctx.Response.StatusCode == 200)
                    //        ctx.Response.StatusCode = 401;
                    //    return Task.CompletedTask;
                    //},
                    //OnRedirectToAccessDenied = ctx =>
                    //{
                    //    if (!ctx.Request.Path.StartsWithSegments("/api") && ctx.Response.StatusCode == 200)
                    //        ctx.Response.StatusCode = 403;
                    //    return Task.CompletedTask;
                    //}
                };
            };

        #endregion
    }
}
