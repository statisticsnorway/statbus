using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models;
using nscreg.Server.Models.Regions;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class RegionsController : Controller
    {
        private readonly RegionsService _regionsService;

        public RegionsController(NSCRegDbContext db)
        {
            _regionsService = new RegionsService(db);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.RegionsView, SystemFunctions.UserView, SystemFunctions.UserEdit, SystemFunctions.UserCreate)]
        public async Task<IActionResult> List([FromQuery] PaginationModel model)
        {
            return Ok(await _regionsService.ListAsync(model));
        }

        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RegionsView)]
        public async Task<IActionResult> List(int id)
        {
            return Ok(await _regionsService.GetAsync(id));
        }

        [HttpPost]
        [SystemFunction(SystemFunctions.RegionsCreate)]
        public async Task<IActionResult> Create([FromBody] RegionM data)
        {
            var region = await _regionsService.CreateAsync(data);
            return Created($"api/regions/{region.Id}", region);
        }

        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RegionsEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] RegionM data)
        {
            await _regionsService.EditAsync(id, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RegionsDelete)]
        public async Task<IActionResult> ToggleDelete(int id, bool delete = false)
        {
            await _regionsService.DeleteUndelete(id, delete);
            return NoContent();
        }
    }
}