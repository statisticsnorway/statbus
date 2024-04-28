using System;
using System.Threading;
using System.Threading.Tasks;

namespace nscreg.ServicesUtils.Interfaces
{
    public interface IJob
    {
        int Interval { get; }
        Task Execute(CancellationToken cancellationToken);
    }
}
