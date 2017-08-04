using System;
using System.Threading;

namespace nscreg.ServicesUtils.Interfaces
{
    public interface IAnalysisJob
    {
        int Interval { get; }
        void Execute(CancellationToken cancellationToken);
        void OnException(Exception e);
    }
}
