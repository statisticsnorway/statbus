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
    /// <summary>
    /// Контроллер связей
    /// </summary>
    [Route("api/[controller]")]
    public class LinksController : Controller
    {
        private readonly LinkService _service;

        public LinksController(NSCRegDbContext context)
        {
            _service = new LinkService(context);
        }

        /// <summary>
        /// Метод создания связи
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
        /// Метод поиска связи
        /// </summary>
        /// <param name="model">Модель поиска связи</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Search([FromQuery] LinkSearchM model)
            => Ok(await _service.Search(model, User.GetUserId()));

        /// <summary>
        /// Метод проверки на возможность быть связанным 
        /// </summary>
        /// <param name="model">Модель</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> CanBeLinked([FromQuery] LinkSubmitM model)
            => Ok(await _service.LinkCanCreate(model, User.GetUserId()));

        /// <summary>
        /// Метод поиска вложенной связи
        /// </summary>
        /// <param name="model">Модель поиска связи</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> Nested([FromQuery] UnitSubmitM model)
            => Ok(await _service.LinksNestedList(model));

        /// <summary>
        /// Метод получения списка связей
        /// </summary>
        /// <param name="model">Модель поиска связи</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.LinksView)]
        public async Task<IActionResult> List([FromQuery] UnitSubmitM model)
            => Ok(await _service.LinksList(model));

        /// <summary>
        /// Метод удаления связи
        /// </summary>
        /// <param name="model">Модель поиска связи</param>
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
