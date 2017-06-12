using System;
using System.IO;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using nscreg.DataUploadService.Jobs;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.DataUploadService
{
    // ReSharper disable once UnusedMember.Global
    public class Program
    {
        // ReSharper disable once UnusedMember.Global
        public static void Main()
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(Path.Combine(AppContext.BaseDirectory))
                .AddJsonFile("appsettings.json", true, true);

            var configuration = builder.Build();

            var settings = configuration.GetSection("AppSettings");
            int dequeueInterval;
            if (!int.TryParse(settings["DequeueInterval"], out dequeueInterval)) dequeueInterval = 60000;

            bool useInMemory;
            bool.TryParse(configuration.GetSection("UseInMemoryDatabase").Value, out useInMemory);
            var ctx = useInMemory
                ? DbContextFactory.CreateInMemory()
                : DbContextFactory.Create(configuration.GetConnectionString("DefaultConnection"));

            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory(extraArguments => new JobService(
                        new QueueJob(ctx, dequeueInterval),
                        new QueueCleanupJob()));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
