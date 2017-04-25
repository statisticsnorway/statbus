using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models.Links;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class LinksController : Controller
    {
        private readonly StatUnitService _service;

        public LinksController(NSCRegDbContext context)
        {
            _service = new StatUnitService(context);
        }

        [HttpPost]
        [SystemFunction(SystemFunctions.LinksCreate)]
        public async Task<IActionResult> Create([FromBody] LinkCommentM model)
        {
            await _service.LinkCreate(model);
            return NoContent();
        }

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Search([FromQuery] LinkSearchM model)
        {
            return Ok(await _service.Search(model));
        }

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> CanBeLinked([FromQuery] LinkSubmitM model)
        {
            var links = await _service.LinkCanCreate(model);
            return Ok(links);
        }

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Nested([FromQuery] UnitSubmitM model)
        {
            var links = await _service.LinksNestedList(model);
            return Ok(links);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> List([FromQuery] UnitSubmitM model)
        {
            var links = await _service.LinksList(model);
            return Ok(links);
        }

        [HttpDelete]
        [SystemFunction(SystemFunctions.LinksDelete)]
        public async Task<IActionResult> Delete([FromBody] LinkCommentM model)
        {
            await _service.LinkDelete(model);
            return NoContent();
        }
    }
}
