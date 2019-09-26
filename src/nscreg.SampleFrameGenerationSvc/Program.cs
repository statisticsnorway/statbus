using System.IO;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.ServicesUtils;
using nscreg.Utilities.Configuration;
using PeterKottas.DotNetCore.WindowsService;
using NLog.Extensions.Logging;

namespace nscreg.SampleFrameGenerationSvc
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

            var ctx = DbContextHelper.Create(connectionSettings);

            ServiceRunner<JobService>.Run(config =>
            {
                config.SetName("nscreg.SampleFrameGenerationSvc");
                config.SetDisplayName("nscreg.SampleFrameGenerationSvc");
                config.SetDescription("nscreg.SampleFrameGenerationSvc");
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
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
