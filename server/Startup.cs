using System;
using System.IO;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;
using Server.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Authorization;
// ReSharper disable UnusedMember.Global

namespace Server
{
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile("appsettings.json", true)
                .AddJsonFile($"appsettings.{env.EnvironmentName}.json", true);

            if (env.IsDevelopment()) builder.AddUserSecrets();

            builder.AddEnvironmentVariables();

            Configuration = builder.Build();
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddAntiforgery(options => options.CookieName = options.HeaderName = "X-XSRF-TOKEN");
            services.AddDbContext<DatabaseContext>(
                // TODO: check environment name here
                //op => op.UseNpgsql(Configuration.GetConnectionString("DefaultConnection")));
                op => op.UseInMemoryDatabase());

            services.AddIdentity<User, Role>(op =>
            {
                op.Password.RequiredLength = 6;
                op.Password.RequireDigit = false;
                op.Password.RequireNonAlphanumeric = false;
                op.Password.RequireLowercase = false;
                op.Password.RequireUppercase = false;

                op.Cookies.ApplicationCookie.ExpireTimeSpan = TimeSpan.FromDays(7);
                op.Cookies.ApplicationCookie.LoginPath = "/Account/LogIn";
                op.Cookies.ApplicationCookie.LogoutPath = "/Account/LogOut";
            })
                .AddEntityFrameworkStores<DatabaseContext>()
                .AddDefaultTokenProviders();

            var defaultPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build();

            services.AddMvcCore(setup =>
            {
                setup.Filters.Add(new AuthorizeFilter(defaultPolicy));
            })
                .AddAuthorization()
                .AddJsonFormatters()
                .AddRazorViewEngine()
                .AddViews();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"));
            loggerFactory.AddDebug();

            app.UseStaticFiles();

            if (env.IsDevelopment())
                app.UseDeveloperExceptionPage();
            else
                app.UseExceptionHandler(new ExceptionHandlerOptions
                {ExceptionHandler = async ctx => await ctx.Response.WriteAsync("Oops!")});

            app.UseIdentity();

            app.UseMvc(routes => routes.MapRoute("default", "{*url}", new {controller = "Home", action = "Index" }));
        }

        public static void Main()
        {
            var rootDir = Directory.GetCurrentDirectory();
            new WebHostBuilder()
                .UseContentRoot(rootDir)
                .UseWebRoot(Path.GetFileName(rootDir) == "server" ? "../public" : "public")
                .UseKestrel()
                .UseIISIntegration()
                .UseStartup<Startup>()
                .Build()
                .Run();
        }
    }
}
