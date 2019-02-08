using System.IO;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.ServicesUtils;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using PeterKottas.DotNetCore.WindowsService;
using NLog.Extensions.Logging;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Класс запуска сервиса анализа
    /// </summary>
    // ReSharper disable once ClassNeverInstantiated.Global
    public class Program
    {
        /// <summary>
        /// Метод запуска сервиса анализа
        /// </summary>
        public static void Main()
        {
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
            var validationSettings = configuration.GetSection(nameof(ValidationSettings)).Get<ValidationSettings>();

            var ctx = DbContextHelper.Create(connectionSettings);

            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName("nscreg.AnalysisService");
                config.SetDisplayName("nscreg.AnalysisService");
                config.SetDescription("nscreg.AnalysisService");
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                        new JobService(
                            new LoggerFactory()
                                .AddNLog()
                                .CreateLogger<Program>(),
                            new AnalysisJob(
                                ctx,
                                statUnitAnalysisRules,
                                dbMandatoryFields,
                                servicesSettings.StatUnitAnalysisServiceDequeueInterval,
                                validationSettings)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
