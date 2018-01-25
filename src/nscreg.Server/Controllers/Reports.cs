using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Services;
using nscreg.Utilities.Configuration;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class ReportsController: Controller
    {
        private readonly ReportService _reportService;

        public ReportsController(NSCRegDbContext context, ReportingSettings settings)
        {
            _reportService = new ReportService(context, settings);

        }

        [HttpGet("[action]")]
        public async Task<IActionResult> GetReportsTree()
        {
            return Ok(await _reportService.GetReportsTree());
        }
    }
}
