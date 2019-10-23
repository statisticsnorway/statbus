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
        private readonly string _rootPath;
        private readonly string _sampleFramesDir;
        public int Interval { get; }

        private readonly ILogger _logger;

        public FileGenerationJob(NSCRegDbContext ctx,
            IConfiguration configuration,
            ServicesSettings servicesSettings,
            ILogger logger)
        {
            _ctx = ctx;
            _sampleFrameExecutor = new SampleFrameExecutor(ctx, configuration);
            Interval = servicesSettings.SampleFrameGenerationServiceDequeueInterval;
            _timeoutMilliseconds = servicesSettings.SampleFrameGenerationServiceCleanupTimeout;
            _rootPath = servicesSettings.RootPath;
            _sampleFramesDir = servicesSettings.SampleFramesDir;
            _logger = logger;
        }

        /// <summary>
        /// Sample frame file generation method
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.LogInformation("sample frame generation/clearing attempt...");

            var moment = DateTime.Now.AddMilliseconds(-_timeoutMilliseconds);
            var sampleFrameToDelete = await _ctx.SampleFrames.FirstOrDefaultAsync(sf => sf.Status == SampleFrameGenerationStatuses.Downloaded
                || (sf.Status == SampleFrameGenerationStatuses.GenerationCompleted && sf.GeneratedDateTime < moment),
                cancellationToken);
            if (sampleFrameToDelete != null)
            {
                _logger.LogInformation("sample frame clearing: {0}", sampleFrameToDelete.Id);
                if (File.Exists(sampleFrameToDelete.FilePath))
                    File.Delete(sampleFrameToDelete.FilePath);
                sampleFrameToDelete.FilePath = null;
                sampleFrameToDelete.GeneratedDateTime = null;
                sampleFrameToDelete.Status = SampleFrameGenerationStatuses.Pending;
                _ctx.SaveChanges();
            } else
            {
                var sampleFrameQueue = await _ctx.SampleFrames.FirstOrDefaultAsync(sf => sf.Status == SampleFrameGenerationStatuses.InQueue, cancellationToken);
                if (sampleFrameQueue != null)
                {
                    _logger.LogInformation("sample frame generation: {0}", sampleFrameQueue.Id);

                    sampleFrameQueue.Status = SampleFrameGenerationStatuses.InProgress;
                    _ctx.SaveChanges();

                    var path = Path.Combine(Path.GetFullPath(_rootPath), _sampleFramesDir);
                    Directory.CreateDirectory(path);
                    var filePath = Path.Combine(path, Guid.NewGuid() + ".csv");
                    try
                    {
                        var fields = JsonConvert.DeserializeObject<List<FieldEnum>>(sampleFrameQueue.Fields);
                        var predicateTree = JsonConvert.DeserializeObject<ExpressionGroup>(sampleFrameQueue.Predicate);
                        await _sampleFrameExecutor.ExecuteToFile(predicateTree, fields, filePath);
                        sampleFrameQueue.FilePath = filePath;
                        sampleFrameQueue.GeneratedDateTime = DateTime.Now;
                        sampleFrameQueue.Status = SampleFrameGenerationStatuses.GenerationCompleted;
                        _ctx.SaveChanges();
                    }
                    catch (Exception e)
                    {
                        sampleFrameQueue.FilePath = null;
                        sampleFrameQueue.GeneratedDateTime = DateTime.Now;
                        sampleFrameQueue.Status = SampleFrameGenerationStatuses.GenerationFailed;
                        _ctx.SaveChanges();
                        if (File.Exists(filePath))
                            File.Delete(filePath);
                        throw new Exception("Error occurred during file generation", e);
                    }
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
