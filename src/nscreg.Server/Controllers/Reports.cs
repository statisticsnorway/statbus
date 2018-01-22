using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class ReportsController: Controller
    {
        private readonly ReportService _reportService;

        public ReportsController(NSCRegDbContext context)
        {
            _reportService = new ReportService(context);

        }

        [HttpGet("[action]")]
        public async Task<IActionResult> GetReportTree()
        {
            return Ok(await _reportService.GetReportTree("admin"));
        }
    }
}
