using System;
using System.Threading;

namespace nscreg.DataSources.Service.Interfaces
{
    internal interface IJob
    {
        int Interval { get; }
        void Execute(CancellationToken cancellationToken);
        void OnException(Exception e);
    }
}