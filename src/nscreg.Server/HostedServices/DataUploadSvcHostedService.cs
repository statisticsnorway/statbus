using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NLog;
using nscreg.Utilities.Configuration;
using Services;
using System;

namespace nscreg.Server.HostedServices
{
    public class DataUploadSvcHostedService: BaseHostedService
    {
        public DataUploadSvcHostedService(IServiceProvider services, IOptions<ServicesSettings> settings) : base(services)
        {
            Logger = LogManager.GetLogger(nameof(SampleFrameGenerationHostedService));
            Services = services;
            TimerInterval = TimeSpan.FromMinutes(settings.Value.DataUploadServiceDequeueInterval);
            Action = async () =>
            {
                using var scope = Services.CreateScope();
                var service = scope.ServiceProvider.GetService<DataUploadSvcService>();
                if (service != null) await service.Execute();
            };
        }
    }
}
