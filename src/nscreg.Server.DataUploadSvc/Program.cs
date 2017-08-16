using System;
using System.IO;
using System.Reflection;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Server.Common;
using nscreg.Server.DataUploadSvc.Jobs;
using nscreg.ServicesUtils;
using nscreg.Utilities;
using PeterKottas.DotNetCore.WindowsService;
using NLog.Extensions.Logging;

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

            var builder = new ConfigurationBuilder()
                .AddJsonFile(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.FullName +
                             SettingsFileName, true, true)
                .AddJsonFile(Directory.GetCurrentDirectory() + SettingsFileName, true, true);
            var configuration = builder.Build();

            var commonSettings = configuration.Get<CommonSettings>();

            var ctx = commonSettings.UseInMemoryDataBase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(commonSettings.ConnectionString);
            var ctxCleanUp = commonSettings.UseInMemoryDataBase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(commonSettings.ConnectionString);

            // TODO: enhance InMemoryDb usage
            if (commonSettings.UseInMemoryDataBase)
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
                        new QueueJob(ctx, commonSettings.DataUploadServiceDequeueInterval, logger),
                        new QueueCleanupJob(ctxCleanUp, commonSettings.DataUploadServiceDequeueInterval,
                            commonSettings.DataUploadServiceCleanupTimeout, logger)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
