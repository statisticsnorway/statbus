using System.Threading.Tasks;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services.Contracts
{
    public interface ISampleFrameService
    {
        Task Create(Expression expression);
        Task Edit(Expression expression);
        void Delete(int id);
    }
}
