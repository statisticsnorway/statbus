using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;

namespace nscreg.AnalysisService
{
    /// <summary>
    /// Класс работы анализа
    /// </summary>
    internal class AnalysisJob : IJob
    {
        private readonly NSCRegDbContext _ctx;
        public int Interval { get; }
        private readonly IStatUnitAnalyzeService _analysisService;
        private readonly ILogger _logger;

        public AnalysisJob(NSCRegDbContext ctx,
            StatUnitAnalysisRules analysisRules,
            DbMandatoryFields dbMandatoryFields,
            int dequeueInterval,
            ValidationSettings validationSettings,
            ILogger logger)
        {
            _ctx = ctx;
            _analysisService = new AnalyzeService(ctx, analysisRules, dbMandatoryFields, validationSettings);
            Interval = dequeueInterval;
            _logger = logger;
        }

        /// <summary>
        /// Метод обработки анализа
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute(CancellationToken cancellationToken)
        {
            _logger.LogInformation("analysis queue attempt...");
            var analysisQueue = await _ctx.AnalysisQueues.LastOrDefaultAsync(aq => aq.ServerEndPeriod == null, cancellationToken);
            if (analysisQueue != null)
            {
                _logger.LogInformation("analizing stat units queue {0}", analysisQueue.Id);
                _analysisService.AnalyzeStatUnits(analysisQueue);
            }
        }
    
        /// <summary>
        /// Метод обработчик исключений
        /// </summary>
        public void OnException(Exception e)
        {
            _logger.LogError("queue exception {0}", e);
            throw new NotImplementedException();
        }
    }
}
