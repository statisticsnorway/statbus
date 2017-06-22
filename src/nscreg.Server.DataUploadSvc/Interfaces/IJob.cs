using System;
using System.Threading;

namespace nscreg.Server.DataUploadSvc.Interfaces
{
    internal interface IJob
    {
        int Interval { get; }
        void Execute(CancellationToken cancellationToken);
        void OnException(Exception e);
    }
}
