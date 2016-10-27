using System.IO;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Server.Models;
using Microsoft.AspNetCore.Http;
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
                op => op.UseNpgsql(Configuration.GetConnectionString("DefaultConnection")));
                //op => op.UseInMemoryDatabase());

            services.AddIdentity<User, IdentityRole>()
                .AddEntityFrameworkStores<DatabaseContext>()
                .AddDefaultTokenProviders();

            services.AddMvcCore()
                .AddAuthorization()
                .AddViews()
                .AddRazorViewEngine()
                .AddJsonFormatters();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"))
                .AddDebug();

            app.UseStaticFiles();

            if (env.IsDevelopment())
                app.UseDeveloperExceptionPage();
            else
                app.UseExceptionHandler(new ExceptionHandlerOptions
                {ExceptionHandler = async ctx => await ctx.Response.WriteAsync("Oops!")});

            app.UseIdentity();

            app.UseMvc(routeBuilder =>
                {
                    routeBuilder.MapRoute("Default",
                        "{controller=Home}/{action=Index}/{id?}");
                });
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
