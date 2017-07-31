using System;
using System.IO;
using System.Reflection;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using nscreg.AnalysisService.Jobs;
using nscreg.Server.Common;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.AnalysisService
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Program
    {
        // ReSharper disable once UnusedMember.Global
        public static void Main()
        {
            Console.WriteLine("starting...");
            var builder = new ConfigurationBuilder()
                .SetBasePath(Path.Combine(AppContext.BaseDirectory))
                .AddJsonFile("appsettings.json", true, true);

            var configuration = builder.Build();

            var settings = configuration.GetSection("AppSettings");
            if (!int.TryParse(settings["DequeueInterval"], out int dequeueInterval)) dequeueInterval = 9999;
            if (!int.TryParse(settings["CleanupTimeout"], out int cleanupTimeout)) cleanupTimeout = 99999;

            bool.TryParse(configuration.GetSection("UseInMemoryDatabase").Value, out bool useInMemory);
            var ctx = useInMemory
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(configuration.GetConnectionString("DefaultConnection"));
            var ctxCleanUp = useInMemory
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(configuration.GetConnectionString("DefaultConnection"));

            // TODO: enhance InMemoryDb usage
            if (useInMemory)
            {
                DbContextHelper.SeedInMemoryData(ctx);
                DbContextHelper.SeedInMemoryData(ctxCleanUp);
            }

            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());

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
