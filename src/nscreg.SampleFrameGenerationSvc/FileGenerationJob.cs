using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Data.Constants;
using Newtonsoft.Json;
using nscreg.Utilities.Enums.Predicate;
using System.Collections.Generic;
using nscreg.Business.SampleFrames;
using nscreg.Server.Common.Services.SampleFrames;
using nscreg.Utilities.Configuration;
using System.IO;

namespace nscreg.SampleFrameGenerationSvc
{
    /// <summary>
    /// Sample frame file generation job class
    /// </summary>
    internal class FileGenerationJob : IJob
    {
        private readonly NSCRegDbContext _ctx;
        private readonly SampleFrameExecutor _sampleFrameExecutor;
        private readonly int _timeoutMilliseconds;
        public int Interval { get; }

        private readonly ILogger _logger;

        public FileGenerationJob(NSCRegDbContext ctx,
            IConfiguration configuration,
            ServicesSettings servicesSettings,
            ILogger logger)
        {
            _ctx = ctx;
            _sampleFrameExecutor = new SampleFrameExecutor(ctx, configuration, servicesSettings);
            Interval = servicesSettings.SampleFrameGenerationServiceDequeueInterval;
            _timeoutMilliseconds = servicesSettings.SampleFrameGenerationServiceCleanupTimeout;
            _logger = logger;
        }

        /// <summary>
        /// Sample frame file generation method
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.LogInformation("sample frame generation attempt...");
            var sampleFrameQueue = await _ctx.SampleFrames.LastOrDefaultAsync(sf => sf.Status == SampleFrameGenerationStatuses.InQueue, cancellationToken);
            if (sampleFrameQueue != null)
            {
                _logger.LogInformation("sample frame generation: {0}", sampleFrameQueue.Id);

                sampleFrameQueue.Status = SampleFrameGenerationStatuses.InProgress;
                _ctx.SaveChanges();

                try
                {
                    var fields = JsonConvert.DeserializeObject<List<FieldEnum>>(sampleFrameQueue.Fields);
                    var predicateTree = JsonConvert.DeserializeObject<ExpressionGroup>(sampleFrameQueue.Predicate);
                    var filePath = await _sampleFrameExecutor.ExecuteToFile(predicateTree, fields);
                    sampleFrameQueue.FilePath = filePath;
                    sampleFrameQueue.GeneratedDateTime = DateTime.Now;
                    sampleFrameQueue.Status = SampleFrameGenerationStatuses.GenerationCompleted;
                    _ctx.SaveChanges();
                }
                catch (Exception e)
                {
                    sampleFrameQueue.Status = SampleFrameGenerationStatuses.GenerationFailed;
                    _ctx.SaveChanges();
                    throw new Exception("Error occurred during file generation", e);
                }
            } else
            {
                var moment = DateTime.Now.AddMilliseconds(-_timeoutMilliseconds);
                var sampleFrameToDelete = await _ctx.SampleFrames.LastOrDefaultAsync(
                    sf => (sf.Status == SampleFrameGenerationStatuses.GenerationCompleted
                        || sf.Status == SampleFrameGenerationStatuses.Downloaded) && sf.GeneratedDateTime < moment,
                    cancellationToken);
                if (sampleFrameToDelete != null && !string.IsNullOrEmpty(sampleFrameToDelete.FilePath))
                {
                    _logger.LogInformation("sample frame clearing: {0}", sampleFrameToDelete.Id);
                    File.Delete(sampleFrameToDelete.FilePath);
                    sampleFrameToDelete.FilePath = null;
                    sampleFrameToDelete.GeneratedDateTime = null;
                    sampleFrameToDelete.Status = SampleFrameGenerationStatuses.Pending;
                    _ctx.SaveChanges();
                }
            }
        }
    
        /// <summary>
        /// Exception handler method
        /// </summary>
        public void OnException(Exception e)
        {
            _logger.LogError("sample frame generation exception {0}", e);
            throw new NotImplementedException();
        }
    }
}
