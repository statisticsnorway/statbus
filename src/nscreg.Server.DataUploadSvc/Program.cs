using System;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NLog.Extensions.Logging;
using nscreg.Server.Common;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils;
using PeterKottas.DotNetCore.WindowsService;
using System.IO;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;

namespace nscreg.Server.DataUploadSvc
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
#pragma warning disable CA1052 // Static holder types should be Static or NotInheritable
    /// <summary>
    /// Data load service launch class
    /// </summary>
    public class Program
#pragma warning restore CA1052 // Static holder types should be Static or NotInheritable
    {
        /// <summary>
        /// Method for starting the data loading service
        /// </summary>
        // ReSharper disable once UnusedMember.Global
        public static void Main()
        {
            var logger = new LoggerFactory()
                .AddConsole()
                .AddNLog()
                .CreateLogger<Program>();

            var configBuilder = new ConfigurationBuilder();
            var baseDirectory = AppContext.BaseDirectory;
            var configuration = configBuilder
                .SetBasePath(baseDirectory)
                .AddJsonFile("appsettings.Shared.json", true)
                .Build();

            const string serviceName = "nscreg.Server.DataUploadSvc";

            ElasticService.ServiceAddress = configuration["ElasticServiceAddress"];
            ElasticService.StatUnitSearchIndexName = configuration["ElasticStatUnitSearchIndexName"];

            Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());

            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName(serviceName);
                config.SetDisplayName(serviceName);
                config.SetDescription(serviceName);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                    {
                        var servicesSettings = configuration
                            .GetSection(nameof(ServicesSettings))
                            .Get<ServicesSettings>();
                        var statUnitAnalysisRules = configuration
                            .GetSection(nameof(StatUnitAnalysisRules))
                            .Get<StatUnitAnalysisRules>();
                        var dbMandatoryFields = configuration
                            .GetSection(nameof(DbMandatoryFields))
                            .Get<DbMandatoryFields>();
                        var validationSettings = configuration
                            .GetSection(nameof(ValidationSettings))
                            .Get<ValidationSettings>();

                        return new JobService(
                            logger,
                            new QueueJob(
                                servicesSettings.DataUploadServiceDequeueInterval,
                                logger,
                                statUnitAnalysisRules,
                                dbMandatoryFields,
                                validationSettings,
                                servicesSettings.DbLogBufferMaxCount
                                ),
                            new QueueCleanupJob(
                                servicesSettings.DataUploadServiceDequeueInterval,
                                servicesSettings.DataUploadServiceCleanupTimeout,
                                logger));
                    });
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e =>
                    {
                        logger.LogError("Service errored with exception : {0}", e.Message);
                    });
                });
            });
        }
    }
}
