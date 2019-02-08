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
using SearchQueryM = nscreg.Server.Common.Models.DataSourcesQueue.SearchQueryM;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер очереди источников данных
    /// </summary>
    [Route("api/[controller]")]
    public class DataSourcesQueueController : Controller
    {
        private readonly DataSourcesQueueService _svc;

        public DataSourcesQueueController(
            NSCRegDbContext ctx,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields mandatoryFields,
            ServicesSettings servicesSettings,
            ValidationSettings validationSettings)
        {
            _svc = new DataSourcesQueueService(
                ctx,
                new CreateService(ctx, statUnitAnalysisRules, mandatoryFields, validationSettings),
                new EditService(ctx, statUnitAnalysisRules, mandatoryFields, validationSettings),
                servicesSettings,
                mandatoryFields);
        }

        /// <summary>
        /// Метод возвращающий список всей очереди источников данных
        /// </summary>
        /// <param name="query">Запрос</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.DataSourcesQueueView)]
        public async Task<IActionResult> GetAllDataSourceQueues([FromQuery] SearchQueryM query) =>
            Ok(await _svc.GetAllDataSourceQueues(query));

        /// <summary>
        /// Метод создания очереди источников данных
        /// </summary>
        /// <param name="data"></param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.DataSourcesQueueAdd)]
        public async Task<IActionResult> Create([FromForm] UploadQueueItemVm data)
        {
            var files = Request.Form.Files;
            if (files.Count < 1) return BadRequest(new {message = nameof(Resource.NoFilesAttached)});
            await _svc.CreateAsync(files, data, User.GetUserId());
            return Ok();
        }

        /// <summary>
        /// Метод получения журнала очереди
        /// </summary>
        /// <param name="queueId">Id очереди</param>
        /// <param name="query">Запрос</param>
        /// <returns></returns>
        [HttpGet("{queueId:int}/log")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetQueueLog(int queueId, [FromQuery] PaginatedQueryM query) =>
            Ok(await _svc.GetQueueLog(queueId, query));

        /// <summary>
        /// Метод получения сведения о журнале
        /// </summary>
        /// <param name="logId">Id журнала</param>
        /// <returns></returns>
        [HttpGet("logs/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetLogDetails(int logId) =>
            Ok(await _svc.GetLogDetails(logId));

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
            Ok(await _svc.GetActivityLogDetailsByStatId(queueId, statId));

        /// <summary>
        /// Метод обновления журнала
        /// </summary>
        /// <param name="logId">Id журнала</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPut("logs/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogEdit)]
        public async Task<IActionResult> UpdateLog(int logId, [FromBody] string data)
        {
            var errors = await _svc.UpdateLog(logId, data, User.GetUserId());
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
            await _svc.DeleteQueue(id, User.GetUserId());
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
            await _svc.DeleteLog(logId, User.GetUserId());
            return NoContent();
        }
    }
}
