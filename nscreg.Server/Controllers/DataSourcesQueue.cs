using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Common.Models.DataSourcesQueue;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class DataSourcesQueueController: Controller
    {
        private readonly DataSourcesQueueService _svc;

        public DataSourcesQueueController(NSCRegDbContext ctx)
        {
            _svc = new DataSourcesQueueService(ctx);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourcesQueueView)]
        public async Task<IActionResult> GetAllDataSourceQueues([FromQuery] SearchQueryM query)
            => Ok(await _svc.GetAllDataSourceQueues(query).ConfigureAwait(false));

        [HttpPost]
        [SystemFunction(SystemFunctions.DataSourcesQueueAdd)]
        public async Task<IActionResult> Create([FromForm] UploadQueueItemVm data)
        {
            var files = Request.Form.Files;
            if (files.Count < 1) return BadRequest(new { message = nameof(Resource.NoFilesAttached) });
            await _svc.CreateAsync(files, data, User.GetUserId());
            return Ok();
        }

        [HttpGet("{queueId:int}/log")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetQueueLog(int queueId, [FromQuery] PaginatedQueryM query)
            => Ok(await _svc.GetQueueLog(queueId, query).ConfigureAwait(false));

        [HttpGet("log/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetLogDetails(int logId)
            => Ok(await _svc.GetLogDetails(logId).ConfigureAwait(false));

        [HttpPut("/log/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogEdit)]
        public async Task<IActionResult> UpdateLog(int logId, [FromForm] UpdateLogM data)
        {
            // await _svc.UpdateLog(logId, data); // should we use create/edit statunit svc directly? or call it from queue svc including log management?
            return NoContent();
        }
    }
}
