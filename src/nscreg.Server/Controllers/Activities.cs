using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер деятельностей
    /// </summary>
    [Route("api/[controller]")]
    public class ActivitiesController : Controller
    {
        private readonly CodeLookupService<ActivityCategory> _service;

        public ActivitiesController(NSCRegDbContext db)
        {
            _service = new CodeLookupService<ActivityCategory>(db);
        }
        /// <summary>
        /// Метод поиска активностей
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));
    }
}
