using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
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

        public AnalysisJob(NSCRegDbContext ctx, StatUnitAnalysisRules analysisRules, DbMandatoryFields dbMandatoryFields, int dequeueInterval, ValidationSettings validationSettings)
        {
            _ctx = ctx;
            _analysisService = new AnalyzeService(ctx, analysisRules, dbMandatoryFields, validationSettings);
            Interval = dequeueInterval;
        }

        /// <summary>
        /// Метод обработки анализа
        /// </summary>
        /// <param name="cancellationToken"></param>
        public async Task Execute(CancellationToken cancellationToken)
        {
            var analysisQueue = await _ctx.AnalysisQueues.LastOrDefaultAsync(aq => aq.ServerEndPeriod == null, cancellationToken);
            if (analysisQueue != null) _analysisService.AnalyzeStatUnits(analysisQueue);
        }

        /// <summary>
        /// Метод обработчик исключений
        /// </summary>
        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
