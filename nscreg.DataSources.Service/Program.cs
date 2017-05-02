using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using nscreg.DataSources.Service.Jobs;
using PeterKottas.DotNetCore.WindowsService;
using PeterKottas.DotNetCore.WindowsService.Interfaces;

namespace nscreg.DataSources.Service
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(Path.Combine(AppContext.BaseDirectory))
                .AddJsonFile("appsettings.json", true, true);
               
            var configuration = builder.Build();
            
            var settings = configuration.GetSection("AppSettings");
            //TODO: REFACTORING var connectionString = configuration.GetConnectionString("DefaultConnection");
            int dequeueInterval;
            if (!int.TryParse(settings["DequeueInterval"], out dequeueInterval)) dequeueInterval = 60000;

            ServiceRunner<JobService>.Run(config =>
            {
                var name = "Nscreg.DataSources.Service";
                config.SetName(name);

                config.Service(serviceConfig =>
                {
                    serviceConfig.ServiceFactory(extraArguments => new JobService(
                        new QueueJob(dequeueInterval),
                        new QueueCleanupJob()
                    ));

                    serviceConfig.OnStart((service, extraArguments) =>
                    {
                        service.Start();
                    });

                    serviceConfig.OnStop(service =>
                    {
                        service.Stop();
                    });

                    serviceConfig.OnError(e =>
                    {
                    });
                });
            });
        }
    }
}
