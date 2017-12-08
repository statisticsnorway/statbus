using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.AnalysisQueue;
using nscreg.Server.Common.Models.DataSourcesQueue;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    ///     Контроллер очереди источников данных
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
        ///     Метод возвращающий список всей очереди источников данных
        /// </summary>
        /// <param name="query">Запрос</param>
        /// <returns></returns>
        [HttpGet]
        public async Task<IActionResult> Get([FromQuery] SearchQueryModel query)
        {
            return Ok(await _svc.GetAsync(query));
        }
    }
}
