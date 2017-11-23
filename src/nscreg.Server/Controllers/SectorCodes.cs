using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.CodeLookup;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер кодов секторов
    /// </summary>
    [Route("api/[controller]")]
    public class SectorCodesController : Controller
    {
        private readonly CodeLookupService<SectorCode> _service;

        public SectorCodesController(NSCRegDbContext dbContext)
        {
            _service = new CodeLookupService<SectorCode>(dbContext);
        }

        /// <summary>
        /// Метод поиска кода сектора
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));

        /// <summary>
        /// Метод получения кода сектора
        /// </summary>
        /// <param name="id">Id сектора</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id) => Ok(await _service.GetById(id));
    }
}
