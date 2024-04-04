using System.Threading.Tasks;
using AutoMapper;
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
    /// <summary>
    /// Links controller
    /// </summary>
    [Route("api/[controller]")]
    public class LinksController : Controller
    {
        private readonly LinkService _service;

        public LinksController(LinkService service)
        {
            _service = service;
        }

        /// <summary>
        /// Link Creation Method
        /// </summary>
        /// <param name="model"></param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.LinksCreate)]
        public async Task<IActionResult> Create([FromBody] LinkCommentM model)
        {
            await _service.LinkCreate(model, User.GetUserId());
            return NoContent();
        }

        /// <summary>
        /// Link Search Method
        /// </summary>
        /// <param name="model">Link Search Model</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Search([FromQuery] LinkSearchM model)
            => Ok(await _service.Search(model, User.GetUserId()));

        /// <summary>
        /// The method of checking for the possibility of being connected
        /// </summary>
        /// <param name="model">model</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> CanBeLinked([FromQuery] LinkSubmitM model)
            => Ok(await _service.LinkCanCreate(model, User.GetUserId()));

        /// <summary>
        /// Nested Link Search Method
        /// </summary>
        /// <param name="model">Link Search Model</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Nested([FromQuery] UnitSubmitM model)
            => Ok(await _service.LinksNestedList(model));

        /// <summary>
        /// Link List Method
        /// </summary>
        /// <param name="model">Link Search Model</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> List([FromQuery] UnitSubmitM model)
            => Ok(await _service.LinksList(model));

        /// <summary>
        /// Link Removal Method
        /// </summary>
        /// <param name="model">Link Search Model</param>
        /// <returns></returns>
        [HttpDelete]
        [SystemFunction(SystemFunctions.LinksDelete)]
        public async Task<IActionResult> Delete([FromBody] LinkCommentM model)
        {
            await _service.LinkDelete(model, User.GetUserId());
            return NoContent();
        }
    }
}
