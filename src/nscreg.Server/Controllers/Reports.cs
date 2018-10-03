using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;
using nscreg.Utilities.Configuration;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class ReportsController: Controller
    {
        private readonly ReportService _reportService;


        public ReportsController(
            NSCRegDbContext context,
            ReportingSettings settings, IConfiguration configuration)
        {
            _reportService = new ReportService(context, settings, configuration);
        }

        [HttpGet("[action]")]
        public async Task<IActionResult> GetReportsTree()
        {
            return Ok(await _reportService.GetReportsTree(User.Identity.Name));
        }
    }
}
