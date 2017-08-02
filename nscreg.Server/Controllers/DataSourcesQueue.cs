using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Server.Common.Services;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using SearchQueryM = nscreg.Server.Common.Models.DataSourceQueues.SearchQueryM;

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

        //[HttpGet]
        //[SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        //public async Task<IActionResult> GetQueueLog([FromQuery] QueueLogQueryM query)
        //    => Ok(await _svc.GetQueueLog(query).ConfigureAwait(false));

        //[HttpGet]
        //[SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        //public async Task<IActionResult> GetLogDetails([FromQuery] int id)
        //    => Ok(await _svc.GetLogDetails(id).ConfigureAwait(false));

        [HttpPost]
        [SystemFunction(SystemFunctions.DataSourcesUpload)]
        public async Task<IActionResult> Create([FromForm] UploadDataSourceVm data)
        {
            var files = Request.Form.Files;
            if (files.Count < 1) return BadRequest(new { message = nameof(Resource.NoFilesAttached) });
            await _svc.CreateAsync(files, data, User.GetUserId());
            return Ok();
        }

        //[HttpPut]
        //[SystemFunction(SystemFunctions.DataSourcesQueueLogEdit)]
        //public async Task<IActionResult> UpdateLog([FromForm] UpdateLogM data)
        //{
        //    await _svc.UpdateLog(data);
        //    return NoContent();
        //}
    }
}
