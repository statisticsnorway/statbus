using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using System.Threading.Tasks;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class SampleFrame : Controller
    {
        private readonly SampleFrameService _sampleFrameService;

        public SampleFrame(NSCRegDbContext context)
        {
            _sampleFrameService = new SampleFrameService(context);
        }
     
        [SystemFunction(SystemFunctions.SampleFrameCreate)]
        public async Task<IActionResult> Create([FromBody] SFExpression expressionTree, SampleFrameM data)
        {
            await _sampleFrameService.CreateAsync(expressionTree, data);
            return NoContent();
        }
      
        [SystemFunction(SystemFunctions.SampleFrameEdit)]
        public async Task<IActionResult> Edit([FromBody] SFExpression expressionTree, SampleFrameM data)
        {
            await _sampleFrameService.EditAsync(expressionTree, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.SampleFrameDelete)]
        public async Task<IActionResult> DeleteAsync(int id)
        {
            await _sampleFrameService.DeleteAsync(id);
            return NoContent();
        }

        public IActionResult View(int id)
        {
            var units = _sampleFrameService.View(id);
            return NoContent();
        }
    }
}
