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
            ServicesSettings servicesSettings)
        {
            _svc = new DataSourcesQueueService(
                ctx,
                new CreateService(ctx, statUnitAnalysisRules, mandatoryFields),
                new EditService(ctx, statUnitAnalysisRules, mandatoryFields),
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
        [HttpGet("log/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogView)]
        public async Task<IActionResult> GetLogDetails(int logId) =>
            Ok(await _svc.GetLogDetails(logId));

        /// <summary>
        /// Метод обновления журнала
        /// </summary>
        /// <param name="logId">Id журнала</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPut("log/{logId:int}")]
        [SystemFunction(SystemFunctions.DataSourcesQueueLogEdit)]
        public async Task<IActionResult> UpdateLog(int logId, [FromBody] string data)
        {
            var errors = await _svc.UpdateLog(logId, data, User.GetUserId());
            return errors != null ? (IActionResult) BadRequest(errors) : NoContent();
        }
    }
}
