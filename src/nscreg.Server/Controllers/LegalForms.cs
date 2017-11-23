using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.CodeLookup;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер правовой формы собственности
    /// </summary>
    [Route("api/[controller]")]
    public class LegalFormsController:Controller
    {
        private readonly CodeLookupService<LegalForm> _service;

        public LegalFormsController(NSCRegDbContext dbContext)
        {
            _service = new CodeLookupService<LegalForm>(dbContext);
        }

        /// <summary>
        /// Метод поиска правовой формы собственности
        /// </summary>
        /// <param name="wildcard">Шаблон запроса</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));

        /// <summary>
        /// Метод получения правовой формы собственности
        /// </summary>
        /// <param name="id">Id правовой формы собственности</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id) => Ok(await _service.GetById(id));
    }
}
