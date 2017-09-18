using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services.Contracts
{
    public interface ISampleFrameService
    {
        Task CreateAsync(SFExpression expressionTree, SampleFrameM data);
        Task EditAsync(SFExpression expressionTree, SampleFrameM data);
        Task DeleteAsync(int id);
        Dictionary<string, string[]> View(int id);
    }
}
