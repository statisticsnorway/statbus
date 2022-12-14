using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.DataSourcesQueue;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Enums;
using SearchQueryM = nscreg.Server.Common.Models.DataSourcesQueue.SearchQueryM;
using AutoMapper;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Data Source Queue Controller
    /// </summary>
    [Route("api/[controller]")]
    public class DataSourcesQueueController : Controller
    {
        private readonly DataSourcesQueueService _dataSourcesQueueService;

        public DataSourcesQueueController(DataSourcesQueueService dataSourcesQueueService)
        {
            _dataSourcesQueueService = dataSourcesQueueService;
        }

        /// <summary>
        /// Method that returns a list of the entire queue of data sources
        /// </summary>
        /// <param name="query">Запрос</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourcesQueueView)]
        public async Task<IActionResult> GetAllDataSourceQueues([FromQuery] SearchQueryM query) =>
            Ok(await _dataSourcesQueueService.GetAllDataSourceQueues(query));

        /// <summary>
        /// Method for creating a data source queue
        /// </summary>
        /// <param name="data"></param>
        /// <returns></returns>
        [HttpPost]
        [DisableRequestSizeLimit]
        [RequestFormLimits(MultipartBodyLengthLimit = int.MaxValue,
        ValueLengthLimit = int.MaxValue)]
        [SystemFunction(SystemFunctions.DataSourcesQueueAdd)]
        public async Task<IActionResult> Create([FromForm] UploadQueueItemVm data)
        {
            var files = Request.Form.Files;
            if (files.Count < 1) return BadRequest(new {message = nameof(Resource.NoFilesAttached)});
            await _dataSourcesQueueService.CreateAsync(files, data, User.GetUserId());
            return Ok();
        }

        /// <summary>
        /// Queue Log Retrieval Method
        /// </summary>
        /// <param name="queueId">queue Id</param>
        /// <param name="query">query</param>
        /// <returns></returns>
        [HttpGet("{queueId:int}/log")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetQueueLog(int queueId, [FromQuery] PaginatedQueryM query) =>
            Ok(await _dataSourcesQueueService.GetQueueLog(queueId, query));

        /// <summary>
        /// Log Information Method
        /// </summary>
        /// <param name="logId">log id</param>
        /// <returns></returns>
        [HttpGet("logs/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetLogDetails(int logId) =>
            Ok(await _dataSourcesQueueService.GetLogDetails(logId));

        /// <summary>
        /// Returns activities uploaded to stat unit
        /// </summary>
        /// <param name="queueId"></param>
        /// <param name="statId"></param>
        /// <returns></returns>
        [AllowAnonymous]
        [HttpGet("queue/{queueId:int}/logs/{statId}")]
        //[SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetActivityLogDetailsByStatId(int queueId, string statId) =>
            Ok(await _dataSourcesQueueService.GetActivityLogDetailsByStatId(queueId, statId));

        /// <summary>
        /// Log Update Method
        /// </summary>
        /// <param name="logId">log id</param>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPut("logs/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogEdit)]
        public async Task<IActionResult> UpdateLog(int logId, [FromBody] string data)
        {
            var errors = await _dataSourcesQueueService.UpdateLog(logId, data, User.GetUserId());
            return errors != null ? (IActionResult) BadRequest(errors) : NoContent();
        }

        /// <summary>
        /// Data source queue delete method - Reject
        /// </summary>
        /// <param name="id">Id of data source queue</param>
        /// <returns></returns>
        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueDelete)]
        public async Task<IActionResult> DeleteQueue(int id)
        {
            await _dataSourcesQueueService.DeleteQueue(id, User.GetUserId());
            return NoContent();
        }


        /// <summary>
        /// Delete uploaded log method - Reject
        /// </summary>
        /// <param name="logId">Id of log</param>
        /// <returns></returns>
        [HttpDelete("logs/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> DeleteLog(int logId)
        {
            await _dataSourcesQueueService.DeleteLog(logId, User.GetUserId());
            return NoContent();
        }
    }
}
