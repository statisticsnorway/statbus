using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Services.SampleFrames
{
    public interface ISampleFrameService
    {
        Task CreateAsync(SFExpression sfExpression, SampleFrame sampleFrame);
        Task EditAsync(SFExpression sfExpression);
        void DeleteAsync(int id);
    }
}