using System;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NLog.Extensions.Logging;
using nscreg.Data;
using nscreg.ServicesUtils;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Analysis Service Launch Class
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Program
    {
        private const string ServiceName = "nscreg.AnalysisService";

        /// <summary>
        /// Analysis Service Launch Method
        /// </summary>
        public static void Main()
        {
            var configuration = new ConfigurationBuilder()
                .SetBasePath(AppContext.BaseDirectory)
                .AddJsonFile("appsettings.Shared.json", true)
                .Build();

            ConfigureAndInitializeAnalysisJob(configuration);
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddSingleton<AnalysisJob>();
        }

            private static void ConfigureAndInitializeAnalysisJob(IConfiguration configuration)
        {
            var logger = new LoggerFactory()
                .AddNLog()
                .CreateLogger<Program>();

            var servicesSettings = configuration
                .GetSection(nameof(ServicesSettings))
                .Validate<ServicesSettings>(logger)
                .Get<ServicesSettings>();

            var statUnitAnalysisRules = configuration
                .GetSection(nameof(StatUnitAnalysisRules))
                .Get<StatUnitAnalysisRules>();

            var dbMandatoryFields = configuration
                .GetSection(nameof(DbMandatoryFields))
                .Get<DbMandatoryFields>();

            var validationSettings = configuration
                .GetSection(nameof(ValidationSettings))
                .Validate<ISettings>(logger)
                .Get<ValidationSettings>();

            var dbContextHelper = new DbContextHelper();
            var ctx = dbContextHelper.CreateDbContext(new string[] { });
            const string serviceName = "nscreg.AnalysisService";
            

            //ServiceRunner<JobService>.Run(config =>
            //{
            //    config.SetName(ServiceName);
            //    config.SetDisplayName(ServiceName);
            //    config.SetDescription(ServiceName);
            //    config.Service(svcConfig =>
            //    {
            //        svcConfig.ServiceFactory((extraArguments, controller) =>
            //            new JobService(
            //                logger,
            //                new AnalysisJob(
            //                    ctx,
            //                    statUnitAnalysisRules,
            //                    dbMandatoryFields,
            //                    servicesSettings.StatUnitAnalysisServiceDequeueInterval,
            //                    validationSettings,
            //                    logger
            //                )));
            //        svcConfig.OnStart((svc, extraArguments) => svc.Start());
            //        svcConfig.OnStop(svc => svc.Stop());
            //        svcConfig.OnError(e =>
            //        {
            //            logger.LogError("Service errored with exception : {0}", e.Message);
            //        });
            //    });
            //});
        }
    }
}
