using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NLog;
using nscreg.Services;
using nscreg.Utilities.Configuration;
using System;

namespace nscreg.Server.HostedServices
{
    public class DataUploadSvcHostedService: BaseHostedService
    {
        public DataUploadSvcHostedService(IServiceProvider services, IOptions<ServicesSettings> settings) : base(services)
        {
            Logger = LogManager.GetLogger(nameof(SampleFrameGenerationHostedService));
            Services = services;
            TimerInterval = TimeSpan.FromSeconds(settings.Value.DataUploadServiceDequeueInterval);
            Action = async () =>
            {
                using var scope = Services.CreateScope();
                var service = scope.ServiceProvider.GetService<DataUploadSvcWorker>();
                if (service != null) await service.Execute();
            };
        }
    }
}
