using System;
using System.IO;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.AnalysisService.Jobs;
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
    public class Program
    {
        /// <summary>
        /// Метод запуска сервиса анализа
        /// </summary>
        public static void Main()
        {
            Console.WriteLine("starting...");

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

            var ctx = DbContextHelper.Create(connectionSettings);

            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
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
                                servicesSettings.StatUnitAnalysisServiceDequeueInterval)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
