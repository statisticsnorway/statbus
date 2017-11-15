using System.IO;
using System.Reflection;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Server.Common;
using nscreg.Server.DataUploadSvc.Jobs;
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
    /// <summary>
    /// Класс запуска сервиса загрузки данных
    /// </summary>
    public class Program
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

            var builder = new ConfigurationBuilder()
                .AddJsonFile(
                    Path.Combine(
                        Directory.GetParent(Directory.GetCurrentDirectory()).Parent.FullName,
                        "appsettings.json"),
                    true,
                    true)
                .AddJsonFile(
                    Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json"),
                    true,
                    true);
            var configuration = builder.Build();

            var connectionSettings = configuration.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
            var servicesSettings = configuration.GetSection(nameof(ServicesSettings)).Get<ServicesSettings>();
            var statUnitAnalysisRules =
                configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();
            var dbMandatoryFields = configuration.GetSection(nameof(DbMandatoryFields)).Get<DbMandatoryFields>();

            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());

            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
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
