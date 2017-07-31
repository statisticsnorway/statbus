using System;
using System.Threading;

namespace nscreg.AnalysisService.Interfaces
{
    internal interface IAnalysisJob
    {
        int Interval { get; }
        void Execute(CancellationToken cancellationToken);
        void OnException(Exception e);
    }
}
