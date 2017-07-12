using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class DataSourcesController : Controller
    {
        private readonly DataSourcesService _svc;

        public DataSourcesController(NSCRegDbContext ctx)
        {
            _svc = new DataSourcesService(ctx);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourcesView)]
        public async Task<IActionResult> GetAllPaged([FromQuery] SearchQueryM data) =>
            Ok(await _svc.GetAllDataSources(data).ConfigureAwait(false));

        [HttpGet("[action]")]
        public IActionResult MappingProperties() => Ok(new PropertyInfoM());

        [HttpPost]
        [SystemFunction(SystemFunctions.DataSourcesCreate)]
        public async Task<IActionResult> Create([FromBody] CreateM data)
        {
            var created = await _svc.Create(data).ConfigureAwait(false);
            return Created($"api/datasources/${created.Id}", created);
        }
    }
}
