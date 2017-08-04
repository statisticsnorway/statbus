using System;
using System.IO;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using nscreg.AnalysisService.Jobs;
using nscreg.ServicesUtils;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.AnalysisService
{
    public class Program
    {
        public static void Main()
        {
            Console.WriteLine("starting...");
            var builder = new ConfigurationBuilder()
                .SetBasePath(Path.Combine(AppContext.BaseDirectory))
                .AddJsonFile("appsettings.json", true, true);

            var configuration = builder.Build();

            var settings = configuration.GetSection("AppSettings");
            if (!int.TryParse(settings["DequeueInterval"], out int dequeueInterval)) dequeueInterval = 9999;

            bool.TryParse(configuration.GetSection("UseInMemoryDatabase").Value, out bool useInMemory);
            var ctx = useInMemory
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(configuration.GetConnectionString("DefaultConnection"));
         
            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory(extraArguments => new JobService(new AnalysisJob(ctx, dequeueInterval)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
