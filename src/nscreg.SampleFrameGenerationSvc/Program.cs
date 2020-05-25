using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NLog.Extensions.Logging;
using nscreg.Data;
using nscreg.ServicesUtils;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using PeterKottas.DotNetCore.WindowsService;
using System.IO;

namespace nscreg.SampleFrameGenerationSvc
{
    /// <summary>
    /// Sample frame generation service startup class
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Program
    {
        /// <summary>
        /// Sample frame generation service startup method
        /// </summary>
        public static void Main()
        {
            var logger = new LoggerFactory()
                .AddNLog()
                .CreateLogger<Program>();
            var configBuilder = new ConfigurationBuilder();
            var baseDirectory = AppContext.BaseDirectory;

            var configuration = configBuilder
                .SetBasePath(baseDirectory)
                .AddJsonFile("appsettings.Shared.json", true)
                .Build();

            var servicesSettings = configuration
                .GetSection(nameof(ServicesSettings))
                .Validate<ServicesSettings>(logger)
                .Get<ServicesSettings>();

            var dbContextHelper = new DbContextHelper();
            var ctx = dbContextHelper.CreateDbContext(new string[] { });
            ctx.Database.SetCommandTimeout(900);

            const string serviceName = "nscreg.SampleFrameGenerationSvc";
            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName(serviceName);
                config.SetDisplayName(serviceName);
                config.SetDescription(serviceName);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                        new JobService(
                            logger,
                            new FileGenerationJob(
                                ctx,
                                configuration,
                                servicesSettings,
                                logger
                                )));
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
