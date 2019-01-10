using System.IO;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Server.Common;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using PeterKottas.DotNetCore.WindowsService;
using NLog.Extensions.Logging;

namespace nscreg.Server.DataUploadSvc
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
#pragma warning disable CA1052 // Static holder types should be Static or NotInheritable
    /// <summary>
    /// Класс запуска сервиса загрузки данных
    /// </summary>
    public class Program
#pragma warning restore CA1052 // Static holder types should be Static or NotInheritable
    {
        /// <summary>
        /// Метод запуска сервиса загрузки данных
        /// </summary>
        // ReSharper disable once UnusedMember.Global
        public static void Main()
        {
            var logger = new LoggerFactory()
                .AddNLog()
                .CreateLogger<Program>();

            var configBuilder = new ConfigurationBuilder();
            var workDir = Directory.GetCurrentDirectory();
            try
            {
                var rootSettingsPath = Path.Combine(workDir, "..", "..");
                if (rootSettingsPath != null)
                    configBuilder.AddJsonFile(
                        Path.Combine(rootSettingsPath, "appsettings.Shared.json"),
                        true);
            }
            catch
            {
                // ignored
            }

            configBuilder
                .AddJsonFile(Path.Combine(workDir, "appsettings.Shared.json"), true)
                .AddJsonFile(Path.Combine(workDir, "appsettings.json"), true);

            var configuration = configBuilder.Build();

            var connectionSettings = configuration.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
            var servicesSettings = configuration.GetSection(nameof(ServicesSettings)).Get<ServicesSettings>();
            var statUnitAnalysisRules =
                configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();
            var dbMandatoryFields = configuration.GetSection(nameof(DbMandatoryFields)).Get<DbMandatoryFields>();
            ElasticService.ServiceAddress = configuration["ElasticServiceAddress"];
            ElasticService.StatUnitSearchIndexName = configuration["ElasticStatUnitSearchIndexName"];

            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());

            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName("nscreg.Server.DataUploadSvc");
                config.SetDisplayName("nscreg.Server.DataUploadSvc");
                config.SetDescription("nscreg.Server.DataUploadSvc");
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                    {
                        var ctx = DbContextHelper.Create(connectionSettings);
                        var ctxCleanUp = DbContextHelper.Create(connectionSettings);
                        // TODO: enhance inmemory db usage
                        if (connectionSettings.ParseProvider() == ConnectionProvider.InMemory)
                        {
                            QueueDbContextHelper.SeedInMemoryData(ctx);
                            QueueDbContextHelper.SeedInMemoryData(ctxCleanUp);
                        }
                        return new JobService(
                            logger,
                            new QueueJob(
                                ctx,
                                servicesSettings.DataUploadServiceDequeueInterval,
                                logger,
                                statUnitAnalysisRules,
                                dbMandatoryFields),
                            new QueueCleanupJob(
                                ctxCleanUp,
                                servicesSettings.DataUploadServiceDequeueInterval,
                                servicesSettings.DataUploadServiceCleanupTimeout,
                                logger));
                    });
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
