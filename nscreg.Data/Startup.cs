using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System.IO;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration.UserSecrets;

[assembly: UserSecretsId("aspnet-nscreg.Data-20161112123049")]
namespace nscreg.Data
{
    public class Startup
    {
        public void ConfigureServices(IServiceCollection services)
        {
            var config = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json", true)
                .AddUserSecrets<Startup>()
                .Build();
            services.AddDbContext<NSCRegDbContext>(op =>
                op.UseNpgsql(config.GetConnectionString("DefaultConnection")));
        }

        public static void Main()
        {
            new WebHostBuilder()
                .UseStartup<Startup>()
                .Build()
                .Run();
        }
    }
}
