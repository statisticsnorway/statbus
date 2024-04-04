using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NLog;
using nscreg.Services;
using nscreg.Utilities.Configuration;
using System;

namespace nscreg.Server.HostedServices
{
    public class AnalysisHostedService : BaseHostedService
    {
        /// <summary>
        /// Конструктор
        /// </summary>
        /// <param name="services"></param>
        /// <param name="settings"></param>
        public AnalysisHostedService(IServiceProvider services, IOptions<ServicesSettings> settings) : base(services)
        {
            Logger = LogManager.GetLogger(nameof(AnalysisHostedService));
            Services = services;
            TimerInterval = TimeSpan.FromSeconds(settings.Value.StatUnitAnalysisServiceDequeueInterval);
            Action = async () =>
            {
                using var scope = Services.CreateScope();
                var service = scope.ServiceProvider.GetService<AnalyseWorker>();
                if (service != null) await service.Execute();
            };
        }
    }
}
