using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models;
using nscreg.Server.Models.Soates;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class SoatesController : Controller
    {
        private readonly SoateService _soatesService;

        public SoatesController(NSCRegDbContext db)
        {
            _soatesService = new SoateService(db);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitCreate, SystemFunctions.StatUnitEdit, SystemFunctions.StatUnitView, SystemFunctions.SoateView)]
        public async Task<IActionResult> List([FromQuery] PaginationModel model)
        {
            return Ok(await _soatesService.ListAsync(model));
        }

        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.SoateView)]
        public async Task<IActionResult> List(int id)
        {
            return Ok(await _soatesService.GetAsync(id));
        }

        [HttpPost]
        [SystemFunction(SystemFunctions.SoateCreate, SystemFunctions.SoateView)]
        public async Task<IActionResult> Create([FromBody] SoateM data)
        {
            var soate = await _soatesService.CreateAsync(data);
            return Created($"api/soates/{soate.Id}", soate);
        }

        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.SoateEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] SoateM data)
        {
            await _soatesService.EditAsync(id, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.SoateDelete)]
        public async Task<IActionResult> ToggleDelete(int id, bool delete = false)
        {
            await _soatesService.DeleteUndelete(id, delete);
            return NoContent();
        }

        [HttpGet("[action]")] //api/soate/search?code=123&limit=50
        public async Task<IActionResult> Search(string code, int limit = 10)
            => Ok(await _soatesService.ListAsync(x => x.Code.Contains(code), limit));

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
                var soate = await _soatesService.GetAsync(searchCode);
                lst.Add(soate?.Name ?? "");
            }
            return Ok(lst);
        }
    }
}
