using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Serialization;
using nscreg.Data;
using nscreg.Data.Entities;
using System;
using System.IO;
using System.Threading.Tasks;
// ReSharper disable UnusedMember.Global

namespace nscreg.Server
{
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile("appSettings.json", true, true)
                .AddJsonFile($"appSettings.{env.EnvironmentName}.json", true)
                .AddEnvironmentVariables();

            if (env.IsDevelopment()) builder.AddUserSecrets();

            Configuration = builder.Build();
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddAntiforgery(options => options.CookieName = options.HeaderName = "X-XSRF-TOKEN");
            services.AddDbContext<NSCRegDbContext>(op =>
            {
                bool flagValue;
                bool.TryParse(Configuration["UseInMemoryDatabase"], out flagValue);
                if (flagValue) op.UseInMemoryDatabase();
                else op.UseNpgsql(Configuration.GetConnectionString("DefaultConnection"));
            });

            services.AddIdentity<User, Role>(ConfigureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();

            services.AddMvcCore(op =>
            {
                op.Filters.Add(new AuthorizeFilter(
                    new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build()));
            })
                .AddAuthorization()
                .AddJsonFormatters(op =>
                    op.ContractResolver = new CamelCasePropertyNamesContractResolver())
                .AddRazorViewEngine()
                .AddViews();

            // Repositories config ⬇️
            // services.AddScoped<I,T>();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory, NSCRegDbContext db)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"))
                .AddDebug();

            app.UseStaticFiles();

            if (env.IsDevelopment()) app.UseDeveloperExceptionPage();
            else app.UseExceptionHandler(builder =>
            {
                builder.Run(
                    async ctx =>
                    {
                        ctx.Response.StatusCode = 500;
                        // TODO: get exception message
                        //var err = ctx.Features.Get<MYEXCEPTIONTYPE>();
                        await ctx.Response.WriteAsync("oops").ConfigureAwait(false);
                    });
            });

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
