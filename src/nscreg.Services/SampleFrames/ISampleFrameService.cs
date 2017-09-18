using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Services.SampleFrames
{
    public interface ISampleFrameService
    {
        Task CreateAsync(SFExpression sfExpression, SampleFrame sampleFrame);
        Task EditAsync(SFExpression sfExpression, SampleFrame sampleFrame);
        Task DeleteAsync(int id);
        Dictionary<string, string[]> View(int id);
    }
}