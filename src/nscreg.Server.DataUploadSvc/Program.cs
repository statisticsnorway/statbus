using System;
using System.IO;
using System.Reflection;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using nscreg.Server.Common;
using nscreg.Server.DataUploadSvc.Jobs;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.Server.DataUploadSvc
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
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
            if (!int.TryParse(settings["DequeueInterval"], out int dequeueInterval)) dequeueInterval = 60000;

            bool.TryParse(configuration.GetSection("UseInMemoryDatabase").Value, out bool useInMemory);
            var ctx = useInMemory
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(configuration.GetConnectionString("DefaultConnection"));
            if (useInMemory) DbContextHelper.SeedInMemoryData(ctx);

            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());

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
