using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System.IO;
using Microsoft.AspNetCore.Hosting;

namespace nscreg.Data
{
    /// <summary>
    /// Класс запуска приложения
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup()
        {
            var workDir = Directory.GetCurrentDirectory();
            var builder = new ConfigurationBuilder()
                .SetBasePath(workDir)
                .AddJsonFile(
                    Path.Combine(
                        workDir,
                        "..", "..", "..", "..",
                        "appsettings.Shared.json"),
                    true)
                .AddJsonFile("appsettings.json", true)
                .AddUserSecrets<Startup>();

            Configuration = builder.Build();
        }

        /// <summary>
        /// Метод конфигурации сервисов
        /// </summary>
        /// <param name="services"></param>
        // ReSharper disable once UnusedMember.Global
        public void ConfigureServices(IServiceCollection services)
        {
            services.AddOptions();
            services.AddDbContext<NSCRegDbContext>(DbContextHelper.ConfigureOptions(Configuration));
        }

        /// <summary>
        /// Метод запуска приложения
        /// </summary>
        public static void Main()
            => new WebHostBuilder()
                .UseStartup<Startup>()
                .Build()
                .Run();
    }
}
