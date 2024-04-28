using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.AnalysisQueue;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Analysis queue controller
    /// </summary>
    [Route("api/[controller]")]
    public class AnalysisQueueController : Controller
    {
        private readonly AnalysisQueueService _analysisQueueService;

        public AnalysisQueueController(AnalysisQueueService analysisQueueService)
        {
            _analysisQueueService = analysisQueueService;
        }

        /// <summary>
        /// Returns paginated analysis queue
        /// </summary>
        /// <param name="query">Filter criterion</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.AnalysisQueueView)]
        public async Task<IActionResult> Get([FromQuery] SearchQueryModel query) => Ok(await _analysisQueueService.GetAsync(query));

        /// <summary>
        /// Creates analysis queue item
        /// </summary>
        /// <param name="data"></param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.AnalysisQueueAdd)]
        public async Task<IActionResult> Create([FromBody] AnalisysQueueCreateModel data) =>
            Ok(await _analysisQueueService.CreateAsync(data, User.GetUserId()));

        /// <summary>
        /// Get analysis queue item log
        /// </summary>
        /// <param name="query"></param>
        /// <returns></returns>
        [HttpGet("{queueId:int}/log")]
        [SystemFunction(SystemFunctions.AnalysisQueueLogView)]
        public async Task<IActionResult> GetQueueLog(LogsQueryModel query) => Ok(await _analysisQueueService.GetLogs(query));

        /// <summary>
        /// Get analysis queue log entry details
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
        [HttpGet("logs/{id:int}")]
        [SystemFunction(SystemFunctions.AnalysisQueueLogView)]
        public async Task<IActionResult> GetLogEntry(int id) => Ok(await _analysisQueueService.GetLogEntry(id));

        /// <summary>
        /// Update statunit with fixes on analysis issues
        /// </summary>
        /// <param name="logId">analysis log entry id</param>
        /// <param name="data">json-serialized statunit model</param>
        /// <returns>errors if update unit is failed, otherwise HTTP 204 No Content</returns>
        [HttpPut("logs/{logId:int}")]
        [SystemFunction(SystemFunctions.AnalysisQueueLogUpdate)]
        public async Task<IActionResult> SubmitLogEntry(int logId, [FromBody]string data)
        {
            var errors = await _analysisQueueService.UpdateLogEntry(logId, data, User.GetUserId());
            return errors != null ? (IActionResult) BadRequest(errors) : NoContent();
        }

        /// <summary>
        /// Delete uploaded log method - Reject
        /// </summary>
        /// <param name="logId">Id of log</param>
        /// <returns></returns>
        [HttpDelete("{logId}")]
        [SystemFunction(SystemFunctions.AnalysisQueueLogDelete)]
        public async Task<IActionResult> DeleteLog(int logId)
        {
            await _analysisQueueService.DeleteAnalyzeLogAsync(logId);
            return NoContent();
        }
    }
}
