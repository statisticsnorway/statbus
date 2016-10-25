using System.IO;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Server.Models;
// ReSharper disable All

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
            services.AddDbContext<DatabaseContext>(
                    options => options.UseInMemoryDatabase()//options.UseNpgsql(Configuration.GetConnectionString("DefaultConnection"))
                );
            services.AddMvc();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
        {
            loggerFactory.AddConsole();
            if (env.IsDevelopment())
                app.UseDeveloperExceptionPage();
            else
                app.UseExceptionHandler(new ExceptionHandlerOptions
                {ExceptionHandler = async ctx => await ctx.Response.WriteAsync("Oops!")});

            app.UseFileServer();
            app.UseMvc(routeBuilder =>
            {
                routeBuilder.MapRoute("Default", "{controller=Home}/{action=Index}/{id?}");
            });
            app.Run(async ctx => await ctx.Response.WriteAsync("Not found!"));
        }

        public static void Main()
        {
            var cwd = Directory.GetCurrentDirectory();
            new WebHostBuilder()
                .UseContentRoot(cwd)
                .UseWebRoot(Path.GetFileName(cwd) == "server" ? "../public" : "public")
                .UseKestrel()
                .UseIISIntegration()
                .UseStartup<Startup>()
                .Build()
                .Run();
        }
    }
}
