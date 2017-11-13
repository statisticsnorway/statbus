using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    ///  Контроллер источников данных
    /// </summary>
    [Route("api/[controller]")]
    public class DataSourcesController : Controller
    {
        private readonly DataSourcesService _svc;

        public DataSourcesController(NSCRegDbContext ctx) => _svc = new DataSourcesService(ctx);

        /// <summary>
        /// Метод получения всех источников данных
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourcesView)]
        public async Task<IActionResult> GetAllPaged([FromQuery] SearchQueryM data) =>
            Ok(await _svc.GetAllDataSources(data));

        /// <summary>
        ///  Метод получения источника данных
        /// </summary>
        /// <param name="id">Id источника данных</param>
        /// <returns></returns>
        [HttpGet("{id:int}")]
        [SystemFunction(SystemFunctions.DataSourcesView)]
        public async Task<IActionResult> GetById(int id) => Ok(await _svc.GetById(id));

        /// <summary>
        /// Метод сопоставления свойств источника данных
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public IActionResult MappingProperties() => Ok(new PropertyInfoM());

        /// <summary>
        /// Метод создания источника данных
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.DataSourcesCreate)]
        public async Task<IActionResult> Create([FromBody] SubmitM data)
        {
            var created = await _svc.Create(data);
            return Created($"api/datasources/${created.Id}", created);
        }

        /// <summary>
        /// Метод редактирования источника данных
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPut("{id:int}")]
        [SystemFunction(SystemFunctions.DataSourcesEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] SubmitM data)
        {
            await _svc.Edit(id, data);
            return NoContent();
        }

        /// <summary>
        /// Метод удаления источника данных
        /// </summary>
        /// <param name="id">Id</param>
        /// <returns></returns>
        [HttpDelete("{id:int}")]
        [SystemFunction(SystemFunctions.DataSourcesDelete)]
        public async Task<IActionResult> Delete(int id)
        {
            await _svc.Delete(id);
            return NoContent();
        }
    }
}
