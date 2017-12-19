using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.AnalysisQueue;
using nscreg.Server.Common.Models.DataSourcesQueue;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    ///     Analysis queue controller
    /// </summary>
    [Route("api/[controller]")]
    public class AnalysisQueueController : Controller
    {
        private readonly AnalysisQueueService _svc;

        public AnalysisQueueController(
            NSCRegDbContext ctx)
        {
            _svc = new AnalysisQueueService(ctx);
        }

        /// <summary>
        ///     Returns paginated analysis queue
        /// </summary>
        /// <param name="query">Filter criterion</param>
        /// <returns></returns>
        [HttpGet]
        public async Task<IActionResult> Get([FromQuery] SearchQueryModel query)
        {
            return Ok(await _svc.GetAsync(query));
        }

        /// <summary>
        /// Creates analysis queue item
        /// </summary>
        /// <param name="data"></param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.AnalysisQueueAdd)]
        public async Task<IActionResult> Create([FromBody] AnalisysQueueCreateModel data)
        {
            return Ok(await _svc.CreateAsync(data, User.GetUserId()));
        }

        [HttpGet("log/{queueId:int}")]
        [SystemFunction(SystemFunctions.AnalysisQueueLogView)]
        [AllowAnonymous]
        public async Task<IActionResult> GetLogDetails(LogsQueryModel query) =>
            Ok(await _svc.GetLogs(query));
    }
}
