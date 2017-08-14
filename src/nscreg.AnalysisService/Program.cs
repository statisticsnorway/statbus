using System;
using System.IO;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using nscreg.AnalysisService.Jobs;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.ServicesUtils;
using nscreg.Utilities;
using PeterKottas.DotNetCore.WindowsService;

namespace nscreg.AnalysisService
{
    public class Program
    {
        private const string SettingsFileName = "\\appsettings.json";

        public static void Main()
        {
            Console.WriteLine("starting...");

            var builder = new ConfigurationBuilder()
                .AddJsonFile(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.FullName +
                             SettingsFileName, true, true)
                .AddJsonFile(Path.Combine(AppContext.BaseDirectory) + SettingsFileName, true, true);
            var configuration = builder.Build();

            var commonSettings = configuration.Get<CommonSettings>();
            var analysisConfiguration = configuration.GetSection("StatUnitAnalysisRules");
          
            var analysisRules = new StatUnitAnalysisRules(
                analysisConfiguration.GetSection("MandatoryFields"),
                analysisConfiguration.GetSection("Connections"),
                analysisConfiguration.GetSection("Orphan"),
                analysisConfiguration.GetSection("Duplicates"));
            
            var ctx = commonSettings.UseInMemoryDataBase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(commonSettings.ConnectionString);
         
            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory(extraArguments => new JobService(new AnalysisJob(ctx, analysisRules,
                        commonSettings.StatUnitAnalysisServiceDequeueInterval)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
