using System.Threading.Tasks;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services.Contracts
{
    public interface ISampleFrameService
    {
        Task Create(SFExpression sfExpression);
        Task Edit(SFExpression sfExpression);
        void Delete(int id);
    }
}
