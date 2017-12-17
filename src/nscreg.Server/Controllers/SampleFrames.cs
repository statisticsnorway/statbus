using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using System.Threading.Tasks;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class SampleFramesController : Controller
    {
        private readonly SampleFramesService _sampleFramesService;

        public SampleFramesController(NSCRegDbContext context)
        {
            _sampleFramesService = new SampleFramesService(context);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.SampleFramesView)]
        public async Task<IActionResult> GetAll(PaginatedQueryM model) =>
            Ok(await _sampleFramesService.GetAll(model));

        [HttpGet("{id:int}")]
        [SystemFunction(SystemFunctions.SampleFramesView)]
        public async Task<IActionResult> GetById(int id) =>
            Ok(await _sampleFramesService.GetById(id));

        [HttpGet("{id:int}/preview")]
        [SystemFunction(SystemFunctions.SampleFramesPreview)]
        public async Task<IActionResult> Preview(int id) =>
            Ok(await _sampleFramesService.Preview(id));

        [HttpPost]
        [SystemFunction(SystemFunctions.SampleFramesCreate)]
        public async Task<IActionResult> Create([FromBody] SampleFrameM data)
        {
            var model = await _sampleFramesService.Create(data, User.GetUserId());
            return Created($"api/sampleframes/{model.Id}", model);
        }

        [HttpPut("{id:int}")]
        [SystemFunction(SystemFunctions.SampleFramesEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] SampleFrameM data)
        {
            await _sampleFramesService.Edit(id, data, User.GetUserId());
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        [SystemFunction(SystemFunctions.SampleFramesDelete)]
        public async Task<IActionResult> DeleteAsync(int id)
        {
            await _sampleFramesService.Delete(id);
            return NoContent();
        }
    }
}
