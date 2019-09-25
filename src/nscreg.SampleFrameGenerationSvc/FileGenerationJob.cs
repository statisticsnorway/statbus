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

namespace nscreg.SampleFrameGenerationSvc
{
    /// <summary>
    /// Sample frame file generation job class
    /// </summary>
    internal class FileGenerationJob : IJob
    {
        private readonly NSCRegDbContext _ctx;
        private readonly SampleFrameExecutor _sampleFrameExecutor;
        public int Interval { get; }

        private readonly ILogger _logger;

        public FileGenerationJob(NSCRegDbContext ctx,
            IConfiguration configuration,
            int dequeueInterval,
            ILogger logger)
        {
            _ctx = ctx;
            _sampleFrameExecutor = new SampleFrameExecutor(ctx, configuration);
            Interval = dequeueInterval;
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
                var fields = JsonConvert.DeserializeObject<List<FieldEnum>>(sampleFrameQueue.Fields);
                var predicateTree = JsonConvert.DeserializeObject<ExpressionGroup>(sampleFrameQueue.Predicate);
                _sampleFrameExecutor.ExecuteToFile(predicateTree, fields);
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
