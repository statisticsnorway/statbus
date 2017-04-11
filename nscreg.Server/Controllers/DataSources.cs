using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.DataSources;
using nscreg.Server.Services;
using System.Threading.Tasks;

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
        public async Task<IActionResult> GetAllPaged(SearchQueryM data) =>
            Ok(await _svc.GetAllDataSources(data).ConfigureAwait(false));

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] CreateM data)
        {
            var created = await _svc.Create(data).ConfigureAwait(false);
            return Created($"api/datasources/${created.Id}", created);
        }
    }
}
