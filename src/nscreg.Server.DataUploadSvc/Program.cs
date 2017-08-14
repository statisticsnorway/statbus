using System;
using System.IO;
using System.Reflection;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Server.Common;
using nscreg.Server.DataUploadSvc.Jobs;
using nscreg.ServicesUtils;
using nscreg.ServicesUtils.Configurations;
using PeterKottas.DotNetCore.WindowsService;
using NLog.Extensions.Logging;
using nscreg.ConfigurationSettings.CommonSettings;

namespace nscreg.Server.DataUploadSvc
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Program
    {
        private const string SettingsFileName = "\\appsettings.json";

        // ReSharper disable once UnusedMember.Global
        public static void Main()
        {
            var logger = new LoggerFactory()
                .AddNLog()
                .CreateLogger<Program>();

            var startup = new Startup(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.FullName,
                Path.Combine(AppContext.BaseDirectory), SettingsFileName);
            var commonSettings = startup.Configuration.GetSection(nameof(CommonSettings)).Get<CommonSettings>();
            var serviceTimeSettings = startup.Configuration.GetSection(nameof(ServiceTimeSettings)).Get<ServiceTimeSettings>();

            var ctx = commonSettings.UseInMemoryDatabase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(commonSettings.ConnectionStrings.DefaultConnection);
            var ctxCleanUp = commonSettings.UseInMemoryDatabase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(commonSettings.ConnectionStrings.DefaultConnection);

            // TODO: enhance InMemoryDb usage
            if (commonSettings.UseInMemoryDatabase)
            {
                QueueDbContextHelper.SeedInMemoryData(ctx);
                QueueDbContextHelper.SeedInMemoryData(ctxCleanUp);
            }

            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());

            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) => new JobService(
                        new QueueJob(ctx, serviceTimeSettings.DequeueInterval, logger),
                        new QueueCleanupJob(ctxCleanUp, serviceTimeSettings.DequeueInterval,
                            serviceTimeSettings.CleanupTimeout, logger)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
