using System;
using System.IO;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using nscreg.AnalysisService.Jobs;
using nscreg.ServicesUtils;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Класс запуска сервиса анализа
    /// </summary>
    public class Program
    {
        private const string SettingsFileName = "\\appsettings.json";

        /// <summary>
        /// Метод запуска сервиса анализа
        /// </summary>
        public static void Main()
        {
            Console.WriteLine("starting...");

            var builder = new ConfigurationBuilder()
                .AddJsonFile(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.FullName +
                             SettingsFileName, true, true)
                .AddJsonFile(Directory.GetCurrentDirectory() + SettingsFileName, true, true);
            var configuration = builder.Build();

            var connectionSettings = configuration.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();
            var servicesSettings = configuration.GetSection(nameof(ServicesSettings)).Get<ServicesSettings>();
            var statUnitAnalysisRules = configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();
            var dbMandatoryFields = configuration.GetSection(nameof(DbMandatoryFields)).Get<DbMandatoryFields>();

            var ctx = connectionSettings.UseInMemoryDataBase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(connectionSettings.ConnectionString);

            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory((extraArguments, controller) =>
                        new JobService(
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
