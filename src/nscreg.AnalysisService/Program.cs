using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NLog.Extensions.Logging;
using nscreg.Data;
using nscreg.ServicesUtils;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using PeterKottas.DotNetCore.WindowsService;
using System.IO;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Analysis Service Launch Class
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Program
    {
        /// <summary>
        /// Analysis Service Launch Method
        /// </summary>
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

            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName("nscreg.AnalysisService");
                config.SetDisplayName("nscreg.AnalysisService");
                config.SetDescription("nscreg.AnalysisService");
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                        new JobService(
                            logger,
                            new AnalysisJob(
                                ctx,
                                statUnitAnalysisRules,
                                dbMandatoryFields,
                                servicesSettings.StatUnitAnalysisServiceDequeueInterval,
                                validationSettings,
                                logger
                                )));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
