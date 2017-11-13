using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Services;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер поиска объекта
    /// </summary>
    [Route("api/[controller]")]
    public class LookupController : Controller
    {
        private readonly LookupService _lookupService;

        public LookupController(NSCRegDbContext db)
        {
            _lookupService = new LookupService(db);
        }

        /// <summary>
        /// Метод получения объекта поиска
        /// </summary>
        /// <param name="lookup"></param>
        /// <returns></returns>
        [HttpGet("{lookup}")]
        public async Task<IActionResult> GetLookup(LookupEnum lookup) =>
            Ok(await _lookupService.GetLookupByEnum(lookup));

        /// <summary>
        /// Метод получения пагинации поиска объекта
        /// </summary>
        /// <param name="lookup">Объект поиска</param>
        /// <param name="searchModel">Поиск модели</param>
        /// <returns></returns>
        [HttpGet("paginated/{lookup}")]
        public async Task<IActionResult> GetPaginateLookup(LookupEnum lookup, [FromQuery] SearchLookupModel searchModel) =>
            Ok(await _lookupService.GetPaginateLookupByEnum(lookup, searchModel));

        /// <summary>
        /// Метод получения объекта поиска по Id
        /// </summary>
        /// <param name="lookup">Объект поиска</param>
        /// <param name="ids">Id</param>
        /// <returns></returns>
        [HttpGet("{lookup}/[action]")]
        public async Task<IActionResult> GetById(LookupEnum lookup, [FromQuery] int[] ids) =>
            Ok(await _lookupService.GetById(lookup, ids));
    }
}
