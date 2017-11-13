using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System.IO;
using Microsoft.AspNetCore.Hosting;
// ReSharper disable UnusedMember.Global

namespace nscreg.Data
{
    // ReSharper disable once ClassNeverInstantiated.Global
    /// <summary>
    /// Класс запуска приложения
    /// </summary>
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup()
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile(
                    Path.Combine(
                        Directory.GetParent(Directory.GetCurrentDirectory()).Parent.Parent.Parent.FullName,
                        "appsettings.json"),
                    true,
                    true)
                .AddJsonFile("appsettings.json", true, true)
                .AddUserSecrets<Startup>();

            Configuration = builder.Build();
        }

        /// <summary>
        /// Метод конфигурации сервисов
        /// </summary>
        /// <param name="services"></param>
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
