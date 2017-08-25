using System.Threading.Tasks;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Services.SampleFrames
{
    public interface ISampleFrameService
    {
        Task CreateAsync(Expression expression);
        Task EditAsync(Expression expression);
        void DeleteAsync(int id);
    }
}