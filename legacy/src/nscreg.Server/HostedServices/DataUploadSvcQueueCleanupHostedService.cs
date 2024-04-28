using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NLog;
using nscreg.Services;
using nscreg.Utilities.Configuration;
using System;

namespace nscreg.Server.HostedServices
{
    public class DataUploadSvcQueueCleanupHostedService : BaseHostedService
    {
        public DataUploadSvcQueueCleanupHostedService(IServiceProvider services, IOptions<ServicesSettings> settings) : base(services)
        {
            Logger = LogManager.GetLogger(nameof(DataUploadSvcQueueCleanupHostedService));
            Services = services;
            TimerInterval = TimeSpan.FromSeconds(settings.Value.DataUploadServiceCleanupTimeout);
            Action = async () =>
            {
                using var scope = Services.CreateScope();
                var service = scope.ServiceProvider.GetService<DataUploadSvcWorker>();
                if (service != null) await service.QueueCleanup();
            };
        }
    }
}
