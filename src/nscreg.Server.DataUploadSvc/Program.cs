using System;
using AutoMapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NLog.Extensions.Logging;
using nscreg.Server.Common;
using nscreg.Server.Common.Services.StatUnit;
using Microsoft.Extensions.DependencyInjection;

namespace nscreg.Server.DataUploadSvc
{
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ClassNeverInstantiated.Global
    /// <summary>
    /// Data load service launch class
    /// </summary>
    public class Program
    {
        /// <summary>
        /// Method for starting the data loading service
        /// </summary>
        public static void Main()
        {
            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName(serviceName);
                config.SetDisplayName(serviceName);
                config.SetDescription(serviceName);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                    {
                       
                        return new JobService(
                            logger,
                            new QueueJob(
                                servicesSettings.DataUploadServiceDequeueInterval,
                                logger,
                                statUnitAnalysisRules,
                                dbMandatoryFields,
                                validationSettings,
                                servicesSettings.DataUploadMaxBufferCount,
                                servicesSettings.PersonGoodQuality,
                                servicesSettings.ElementsForRecreateContext, mapper),
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
