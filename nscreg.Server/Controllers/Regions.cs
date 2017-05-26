using System.Collections.Generic;
using System.Text.RegularExpressions;
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
        private readonly RegionService _regionsService;

        public RegionsController(NSCRegDbContext db)
        {
            _regionsService = new RegionService(db);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitCreate, SystemFunctions.StatUnitEdit, SystemFunctions.StatUnitView, SystemFunctions.RegionsView)]
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
        [SystemFunction(SystemFunctions.RegionsCreate, SystemFunctions.RegionsView)]
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

        [HttpGet("[action]")]
        public async Task<IActionResult> Search(string code, int limit = 10)
            => Ok(await _regionsService.ListAsync(x => x.Code.Contains(code), limit));

        [HttpGet("{code}")]
        public async Task<IActionResult> GetAddress(string code)
        {
            if (!Regex.IsMatch(code, @"\d{14}"))
                return NotFound();
            var digitCounts = new[] { 3, 5, 8, 11, 14 }; //number of digits to parse
            var lst = new List<string>();
            foreach (var item in digitCounts)
            {
                var searchCode = code.Substring(0, item);
                var region = await _regionsService.GetAsync(searchCode);
                lst.Add(region?.Name ?? "");
            }
            return Ok(lst);
        }
    }
}
