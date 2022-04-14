using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    ///  Data source controller
    /// </summary>
    [Route("api/[controller]")]
    public class DataSourcesController : Controller
    {
        private readonly DataSourcesService _svc;

        public DataSourcesController(DataSourcesService svc)
        {
            _svc = svc;
        }

        /// <summary>
        /// The method of obtaining all data sources
        /// </summary>
        /// <param name="data">Data</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourcesView)]
        public async Task<IActionResult> GetAllPaged([FromQuery] SearchQueryM data) =>
            Ok(await _svc.GetAllDataSources(data));

        /// <summary>
        ///  Data Source Retrieval Method
        /// </summary>
        /// <param name="id">data Id</param>
        /// <returns></returns>
        [HttpGet("{id:int}")]
        [SystemFunction(SystemFunctions.DataSourcesView)]
        public async Task<IActionResult> GetById(int id) => Ok(await _svc.GetById(id));

        /// <summary>
        /// Data Source Properties Mapping Method
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public IActionResult MappingProperties() => Ok(new PropertyInfoM());

        /// <summary>
        /// Data Source Creation Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.DataSourcesCreate)]
        public async Task<IActionResult> Create([FromBody] SubmitM data)
        {
            var created = await _svc.Create(data, User.GetUserId());
            return Created($"api/datasources/${created.Id}", created);
        }

        /// <summary>
        /// Data Source Editing Method
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPut("{id:int}")]
        [SystemFunction(SystemFunctions.DataSourcesEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] SubmitM data)
        {
            await _svc.Edit(id, data, User.GetUserId());
            return NoContent();
        }

        /// <summary>
        /// Data Source Deletion Method
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
