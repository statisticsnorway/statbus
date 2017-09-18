using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services.Contracts
{
    public interface ISampleFrameService
    {
        Task Create(SFExpression expressionTree, SampleFrameM data);
        Task Edit(SFExpression expressionTree, SampleFrameM data);
        void Delete(int id);
        Dictionary<string, string[]> View(int id);
    }
}
