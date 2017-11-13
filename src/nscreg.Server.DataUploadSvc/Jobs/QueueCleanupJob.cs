using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Server.Common.Services.DataSources;
using nscreg.ServicesUtils.Interfaces;

namespace nscreg.Server.DataUploadSvc.Jobs
{
    /// <summary>
    /// Класс по работе очистки очереди
    /// </summary>
    public class QueueCleanupJob : IJob
    {
        public int Interval { get; }

        private readonly int _timeout;
        private readonly ILogger _logger;
        private readonly QueueService _queueSvc;

        public QueueCleanupJob(NSCRegDbContext ctx, int dequeueInterval, int timeout, ILogger logger)
        {
            Interval = dequeueInterval;
            _queueSvc = new QueueService(ctx);
            _timeout = timeout;
            _logger = logger;
        }

        /// <summary>
        /// Метод выполнения очистки очереди
        /// </summary>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.LogInformation("cleaning up...");
            await _queueSvc.ResetDequeuedByTimeout(_timeout);
        }

        /// <summary>
        /// Метод обработчик исключений
        /// </summary>
        public void OnException(Exception e)
        {
            _logger.LogError("cleaning up exception {0}", e);
            throw new NotImplementedException();
        }
    }
}
