using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NLog;
using nscreg.Services;
using nscreg.Utilities.Configuration;
using System;

namespace nscreg.Server.HostedServices
{
    public class SampleFrameGenerationHostedService : BaseHostedService
    {
        /// <summary>
        /// Конструктор
        /// </summary>
        /// <param name="services"></param>
        /// <param name="settings"></param>
        public SampleFrameGenerationHostedService(IServiceProvider services, IOptions<ServicesSettings> settings) : base(services)
        {
            Logger = LogManager.GetLogger(nameof(SampleFrameGenerationHostedService));
            Services = services;
            TimerInterval = TimeSpan.FromSeconds(settings.Value.SampleFrameGenerationServiceDequeueInterval);
            Action = async () =>
            {
                using var scope = Services.CreateScope();
                var service = scope.ServiceProvider.GetService<FileGenerationWorker>();
                if (service != null) await service.Execute();
            };
        }
    }
}
