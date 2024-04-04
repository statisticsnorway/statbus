using System;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using Newtonsoft.Json;
using nscreg.Utilities.Enums.Predicate;
using System.Collections.Generic;
using nscreg.Business.SampleFrames;
using nscreg.Server.Common.Services.SampleFrames;
using nscreg.Utilities.Configuration;
using System.IO;
using Microsoft.Extensions.Options;
using NLog;
using System.Reflection;

namespace nscreg.Services
{
    /// <summary>
    /// Sample frame file generation job class
    /// </summary>
    public class FileGenerationWorker
    {
        public int Interval { get; }
        private readonly NSCRegDbContext _ctx;
        private readonly SampleFrameExecutor _sampleFrameExecutor;
        private static Logger _logger = LogManager.GetCurrentClassLogger();
        private readonly int _timeoutMilliseconds;
        private readonly string _sampleFramesDir;

        public FileGenerationWorker(NSCRegDbContext ctx,
            IOptions<ServicesSettings> servicesSettings, SampleFrameExecutor executor)
        {
            _ctx = ctx;
            _sampleFrameExecutor = executor;
            Interval = servicesSettings.Value.SampleFrameGenerationServiceDequeueInterval;
            _timeoutMilliseconds = servicesSettings.Value.SampleFrameGenerationServiceCleanupTimeout;
            _sampleFramesDir = servicesSettings.Value.SampleFramesDir;
        }

        /// <summary>
        /// Sample frame file generation method
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute()
        {
            _logger.Info("sample frame generation/clearing attempt...");

            var moment = DateTimeOffset.UtcNow.AddMilliseconds(-_timeoutMilliseconds);
            var sampleFrameToDelete = await _ctx.SampleFrames.FirstOrDefaultAsync(sf => sf.Status == SampleFrameGenerationStatuses.Downloaded
                || (sf.Status == SampleFrameGenerationStatuses.GenerationCompleted && sf.GeneratedDateTime < moment));
            if (sampleFrameToDelete != null)
            {
                _logger.Info("sample frame clearing: {0}", sampleFrameToDelete.Id);
                if (File.Exists(sampleFrameToDelete.FilePath))
                    File.Delete(sampleFrameToDelete.FilePath);
                sampleFrameToDelete.FilePath = null;
                sampleFrameToDelete.GeneratedDateTime = null;
                sampleFrameToDelete.Status = SampleFrameGenerationStatuses.Pending;
                _ctx.SaveChanges();
            } else
            {
                var sampleFrameQueue = await _ctx.SampleFrames.FirstOrDefaultAsync(sf => sf.Status == SampleFrameGenerationStatuses.InQueue);
                if (sampleFrameQueue != null)
                {
                    _logger.Info("sample frame generation: {0}", sampleFrameQueue.Id);

                    sampleFrameQueue.Status = SampleFrameGenerationStatuses.InProgress;
                    _ctx.SaveChanges();

                    var path = Path.Combine(Path.GetFullPath(AssemblyDirectory), _sampleFramesDir);
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

        private string AssemblyDirectory
        {
            get
            {
                string codeBase = Assembly.GetExecutingAssembly().Location;
                UriBuilder uri = new UriBuilder(codeBase);
                string path = Uri.UnescapeDataString(uri.Path);
                return Path.GetDirectoryName(path);
            }
        }
    }
}
