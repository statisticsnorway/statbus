using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models.DataSourceQueues;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class DataSourceQueuesController: Controller
    {
        private DataSourceQueuesService _svc;
        public DataSourceQueuesController(NSCRegDbContext ctx)
        {
            _svc = new DataSourceQueuesService(ctx);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourceQueuesView)]
        public async Task<IActionResult> GetAllDataSourceQueues([FromQuery] SearchQueryM query)
        {
            return Ok(await _svc.GetAllDataSourceQueues(query).ConfigureAwait(false));
        }
    }
}
