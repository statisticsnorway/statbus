using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using System.Threading.Tasks;
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
        public async Task<IActionResult> Create([FromBody] Expression data)
        {
            await _sampleFrameService.Create(data);
            return NoContent();
        }
      
        [SystemFunction(SystemFunctions.SampleFrameEdit)]
        public async Task<IActionResult> Edit([FromBody] Expression data)
        {
            await _sampleFrameService.Edit(data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.SampleFrameDelete)]
        public IActionResult Delete(int id)
        {
            _sampleFrameService.Delete(id);
            return NoContent();
        }
    }
}
