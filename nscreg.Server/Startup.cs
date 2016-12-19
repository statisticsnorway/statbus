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
                .AddJsonFile("appSettings.json", true, true)
                .AddJsonFile($"appSettings.{env.EnvironmentName}.json", true)
                .AddEnvironmentVariables();

            if (env.IsDevelopment()) builder.AddUserSecrets();

            Configuration = builder.Build();
            CurrentEnvironment = env;
        }

        public void ConfigureServices(IServiceCollection services)
        {
            AutoMapperConfiguration.Configure();

            services.AddAntiforgery(options => options.CookieName = options.HeaderName = "X-XSRF-TOKEN");
            services.AddDbContext<NSCRegDbContext>(op =>
            {
                var useInMemoryDb = Configuration.GetValue<bool>("UseInMemoryDatabase");
                if (useInMemoryDb) op.UseInMemoryDatabase();
                else op.UseNpgsql(
                    Configuration.GetConnectionString("DefaultConnection"),
                    op2 => op2.MigrationsAssembly("nscreg.Data"));
            });

            services.AddIdentity<User, Role>(ConfigureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();

            services.AddMvcCore(op =>
            {
                op.Filters.Add(new AuthorizeFilter(
                    new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build()));
                op.Filters.Add(new ValidateModelStateAttribute());
            })
                .AddMvcOptions(o =>
                {
                    if (CurrentEnvironment.IsDevelopment())
                        o.Filters.Add(new GlobalExceptionFilter(_loggerFactory));
                })
                .AddAuthorization()
                .AddJsonFormatters(op =>
                    op.ContractResolver = new CamelCasePropertyNamesContractResolver())
                .AddRazorViewEngine()
                .AddViews();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"))
                .AddDebug();

            _loggerFactory = loggerFactory;

            app.UseStaticFiles();

            app.UseIdentity()
                .UseMvc(routes =>
                    routes.MapRoute("default", "{*url}", new { controller = "Home", action = "Index" }));

            if (env.IsDevelopment())
                NSCRegDbInitializer.Seed(app.ApplicationServices.GetService<NSCRegDbContext>());
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

        private Action<IdentityOptions> ConfigureIdentity = op =>
        {
            // password settings
            op.Password.RequiredLength = 6;
            op.Password.RequireDigit = false;
            op.Password.RequireNonAlphanumeric = false;
            op.Password.RequireLowercase = false;
            op.Password.RequireUppercase = false;
            // auth settings
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
            };
        };
    }
}
