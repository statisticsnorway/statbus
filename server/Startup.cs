using System.IO;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Server.Models;
// ReSharper disable UnusedMember.Global

namespace Server
{
    public class Startup
    {
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

        private IConfiguration Configuration { get; }

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

            app.UseStaticFiles()
                .UseIdentity();

            if (env.IsDevelopment())
                app.UseDeveloperExceptionPage();
            else
                app.UseExceptionHandler(new ExceptionHandlerOptions
                {ExceptionHandler = async ctx => await ctx.Response.WriteAsync("Oops!")});

            app.UseFileServer()
                .UseMvc(routeBuilder =>
                {
                    routeBuilder.MapRoute("default", "{*url}", new {controller = "Home", action = "Index"});
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
