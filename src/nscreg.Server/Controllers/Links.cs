using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.Links;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class LinksController : Controller
    {
        private readonly LinkService _service;

        public LinksController(NSCRegDbContext context)
        {
            _service = new LinkService(context);
        }

        [HttpPost]
        [SystemFunction(SystemFunctions.LinksCreate)]
        public async Task<IActionResult> Create([FromBody] LinkCommentM model)
        {
            await _service.LinkCreate(model, User.GetUserId());
            return NoContent();
        }

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Search([FromQuery] LinkSearchM model)
            => Ok(await _service.Search(model));

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> CanBeLinked([FromQuery] LinkSubmitM model)
            => Ok(await _service.LinkCanCreate(model, User.GetUserId()));

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Nested([FromQuery] UnitSubmitM model)
            => Ok(await _service.LinksNestedList(model));

        [HttpGet]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> List([FromQuery] UnitSubmitM model)
            => Ok(await _service.LinksList(model));

        [HttpDelete]
        [SystemFunction(SystemFunctions.LinksDelete)]
        public async Task<IActionResult> Delete([FromBody] LinkCommentM model)
        {
            await _service.LinkDelete(model, User.GetUserId());
            return NoContent();
        }
    }
}
