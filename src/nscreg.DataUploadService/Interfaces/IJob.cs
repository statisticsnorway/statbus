using System;
using System.Threading;

namespace nscreg.DataUploadService.Interfaces
{
    internal interface IJob
    {
        int Interval { get; }
        void Execute(CancellationToken cancellationToken);
        void OnException(Exception e);
    }
}
