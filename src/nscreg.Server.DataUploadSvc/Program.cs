using System.IO;
using System.Reflection;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Server.Common;
using nscreg.Server.DataUploadSvc.Jobs;
using nscreg.ServicesUtils;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using PeterKottas.DotNetCore.WindowsService;
using NLog.Extensions.Logging;

namespace nscreg.Server.DataUploadSvc
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
    /// <summary>
    /// Класс запуска сервиса загрузки данных
    /// </summary>
    public class Program
    {
        private const string SettingsFileName = "\\appsettings.json";

        /// <summary>
        /// Метод запуска сервиса загрузки данных
        /// </summary>
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

            var connectionSettings = configuration.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
            var servicesSettings = configuration.GetSection(nameof(ServicesSettings)).Get<ServicesSettings>();
            var statUnitAnalysisRules = configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();

            var ctx = connectionSettings.UseInMemoryDataBase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(connectionSettings.ConnectionString);
            var ctxCleanUp = connectionSettings.UseInMemoryDataBase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(connectionSettings.ConnectionString);

            // TODO: enhance InMemoryDb usage
            if (connectionSettings.UseInMemoryDataBase)
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
                        new QueueJob(ctx, servicesSettings.DataUploadServiceDequeueInterval, logger, statUnitAnalysisRules),
                        new QueueCleanupJob(ctxCleanUp, servicesSettings.DataUploadServiceDequeueInterval,
                            servicesSettings.DataUploadServiceCleanupTimeout, logger)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
