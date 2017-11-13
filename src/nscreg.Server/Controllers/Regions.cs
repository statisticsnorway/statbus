using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.Regions;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер регионов
    /// </summary>
    [Route("api/[controller]")]
    public class RegionsController : Controller
    {
        private readonly RegionService _regionsService;

        public RegionsController(NSCRegDbContext db)
        {
            _regionsService = new RegionService(db);
        }

        /// <summary>
        /// Метод получения списка регионов
        /// </summary>
        /// <param name="model">Модель запроса</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(
            SystemFunctions.StatUnitCreate,
            SystemFunctions.StatUnitEdit,
            SystemFunctions.StatUnitView,
            SystemFunctions.RegionsView)]
        public async Task<IActionResult> List([FromQuery] PaginatedQueryM model) =>
            Ok(await _regionsService.ListAsync(model));

        /// <summary>
        /// Метод получения региона
        /// </summary>
        /// <param name="id">Id</param>
        /// <returns></returns>
        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RegionsView)]
        public async Task<IActionResult> List(int id) => Ok(await _regionsService.GetAsync(id));

        /// <summary>
        /// Метод создания региона
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.RegionsCreate, SystemFunctions.RegionsView)]
        public async Task<IActionResult> Create([FromBody] RegionM data)
        {
            var region = await _regionsService.CreateAsync(data);
            return Created($"api/regions/{region.Id}", region);
        }

        /// <summary>
        /// Метод редактирования региона
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RegionsEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] RegionM data)
        {
            await _regionsService.EditAsync(id, data);
            return NoContent();
        }

        /// <summary>
        /// Метод переключения удалённости
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="delete">Флаг удалённости</param>
        /// <returns></returns>
        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RegionsDelete)]
        public async Task<IActionResult> ToggleDelete(int id, bool delete = false)
        {
            await _regionsService.DeleteUndelete(id, delete);
            return NoContent();
        }

        /// <summary>
        /// Метод поиска региона
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <param name="limit">Ограничение</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> Search(string wildcard, int limit = 10) =>
            Ok(await _regionsService.ListAsync(
                x =>
                    x.Code.Contains(wildcard)
                    || x.Name.ToLower().Contains(wildcard.ToLower())
                    || x.AdminstrativeCenter.Contains(wildcard),
                limit));

        /// <summary>
        /// Метод получения списка адресов
        /// </summary>
        /// <param name="code">Код региона</param>
        /// <returns></returns>
        [HttpGet("{code}")]
        public async Task<IActionResult> GetAddress(string code)
        {
            if (!Regex.IsMatch(code, @"\d{14}"))
                return NotFound();
            var digitCounts = new[] {3, 5, 8, 11, 14}; //number of digits to parse
            var lst = new List<string>();
            foreach (var item in digitCounts)
            {
                var searchCode = code.Substring(0, item);
                var region = await _regionsService.GetAsync(searchCode);
                lst.Add(region?.Name ?? "");
            }
            return Ok(lst);
        }

        /// <summary>
        /// Метод получения списка кодов региона по диапазону
        /// </summary>
        /// <param name="start">Начало</param>
        /// <param name="end">Конец</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> GetAreasList(string start = "417", string end = "") =>
            Ok(await _regionsService.GetByPartCode(start, end));

        /// <summary>
        /// Метод полечения дерева регионов
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> GetRegionTree() => Ok(await _regionsService.GetRegionTreeAsync());
    }
}
