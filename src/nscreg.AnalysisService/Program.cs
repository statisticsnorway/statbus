using System;
using System.IO;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using nscreg.AnalysisService.Jobs;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.ServicesUtils;
using PeterKottas.DotNetCore.WindowsService;
using nscreg.ServicesUtils.Configurations;
using nscreg.ConfigurationSettings.CommonSettings;

namespace nscreg.AnalysisService
{
    public class Program
    {
        private const string SettingsFileName = "\\appsettings.json";

        public static void Main()
        {
            Console.WriteLine("starting...");
            var startup = new Startup(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.FullName,
                Path.Combine(AppContext.BaseDirectory), SettingsFileName);
            var commonSettings = startup.Configuration.GetSection(nameof(CommonSettings)).Get<CommonSettings>();
            var serviceTimeSettings = startup.Configuration.GetSection(nameof(ServiceTimeSettings)).Get<ServiceTimeSettings>();
           
            var analysisConfiguration = startup.Configuration.GetSection("StatUnitAnalysisRules");
          
            var analysisRules = new StatUnitAnalysisRules(
                analysisConfiguration.GetSection("MandatoryFields"),
                analysisConfiguration.GetSection("Connections"),
                analysisConfiguration.GetSection("Orphan"),
                analysisConfiguration.GetSection("Duplicates"));
            
            var ctx = commonSettings.UseInMemoryDatabase
                ? DbContextHelper.CreateInMemoryContext()
                : DbContextHelper.CreateDbContext(commonSettings.ConnectionStrings.DefaultConnection);
         
            ServiceRunner<JobService>.Run(config =>
            {
                var name = Assembly.GetEntryAssembly().GetName().Name;
                config.SetName(name);
                config.Service(svcConfig =>
                {
                    svcConfig.ServiceFactory(extraArguments => new JobService(new AnalysisJob(ctx, analysisRules,
                        serviceTimeSettings.DequeueInterval)));
                    svcConfig.OnStart((svc, extraArguments) => svc.Start());
                    svcConfig.OnStop(svc => svc.Stop());
                    svcConfig.OnError(e => { });
                });
            });
        }
    }
}
