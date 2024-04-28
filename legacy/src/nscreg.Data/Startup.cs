using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System.IO;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Builder;

namespace nscreg.Data
{
    /// <summary>
    /// Application Launch Class
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup()
        {
            var workDir = Directory.GetCurrentDirectory();
            var appsettingsSharedPath = Path.Combine(
                workDir,
                "..", "..",
                "appsettings.Shared.json");
            var builder = new ConfigurationBuilder()
                .SetBasePath(workDir)
                .AddJsonFile(appsettingsSharedPath, false)
                //.AddJsonFile("appsettings.json", true)
                .AddUserSecrets<Startup>();
            Configuration = builder.Build();
        }

        /// <summary>
        /// Service Configuration Method
        /// </summary>
        /// <param name="services"></param>
        // ReSharper disable once UnusedMember.Global
        public void ConfigureServices(IServiceCollection services)
        {
            services.AddOptions();
            services.AddDbContext<NSCRegDbContext>(DbContextHelper.ConfigureOptions(Configuration));
        }

        public void Configure(IApplicationBuilder app)
        {

        }
        /// <summary>
        /// Application Launch Method
        /// </summary>
        public static void Main(string[] args)
            => CreateWebHostBuilder(args).Build().Run();

        public static IWebHostBuilder CreateWebHostBuilder(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
                .UseStartup<Startup>();
    }
}
