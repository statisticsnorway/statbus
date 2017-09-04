using System.Threading.Tasks;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Services.SampleFrames
{
    public interface ISampleFrameService
    {
        Task CreateAsync(SFExpression sfExpression);
        Task EditAsync(SFExpression sfExpression);
        void DeleteAsync(int id);
    }
}