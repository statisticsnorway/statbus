using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System.IO;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Options;
using nscreg.ConfigurationSettings.CommonSettings;

// ReSharper disable UnusedMember.Global

namespace nscreg.Data
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup()
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("../appsettings.json", true, true)
                .AddJsonFile("appsettings.json", true, true)
                .AddUserSecrets<Startup>();

            Configuration = builder.Build();
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddOptions();
            services.Configure<ConnectionStrings>(cs => Configuration.GetSection(nameof(ConnectionStrings)).Bind(cs));
            services.AddScoped(cfg => cfg.GetService<IOptions<ConnectionStrings>>().Value);

            services.AddDbContext<NSCRegDbContext>(op =>
                op.UseNpgsql(Configuration.GetConnectionString(nameof(ConnectionStrings.DefaultConnection))));
        }

        public static void Main()
            => new WebHostBuilder()
                .UseStartup<Startup>()
                .Build()
                .Run();
    }
}
