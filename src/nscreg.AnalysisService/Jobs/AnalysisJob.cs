using System;
using System.Threading;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration.StatUnitAnalysis;

namespace nscreg.AnalysisService.Jobs
{
    internal class AnalysisJob : IJob
    {
        public int Interval { get; }
        private readonly IStatUnitAnalyzeService _analysisService;

        public AnalysisJob(NSCRegDbContext ctx, StatUnitAnalysisRules analysisRules, int dequeueInterval)
        {
            Interval = dequeueInterval;
            _analysisService = new AnalyzeService(ctx, new StatUnitAnalyzer(analysisRules));
        }

        public void Execute(CancellationToken cancellationToken)
        {
            _analysisService.AnalyzeStatUnits();
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
