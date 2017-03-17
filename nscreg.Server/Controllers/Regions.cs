using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
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
        public async Task<IActionResult> List()
        {
            return Ok(await _regionsService.ListAsync());
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> List(int id)
        {
            return Ok(await _regionsService.GetAsync(id));
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RegionM data)
        {
            var region = await _regionsService.CreateAsync(data);
            return Created($"api/regions/{region.Id}", region);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Edit(int id, [FromBody] RegionM data)
        {
            await _regionsService.EditAsync(id, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async  Task<IActionResult> Delete(int id)
        {
            await _regionsService.Delete(id);
            return NoContent();
        }
    }
}