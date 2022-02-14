using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;
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

        private HttpResponseMessage MakeResponse(byte[] csvBytes, string fileName)
        {
            HttpResponseMessage result = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(csvBytes) };
            result.Content.Headers.ContentType = new MediaTypeHeaderValue("text/csv");
            result.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment") { FileName = fileName };
            return result;
        }

        [HttpPost]
        [SystemFunction(SystemFunctions.Download)]
        public async Task<HttpResponseMessage> DownloadStatUnitEnterpriseCsv()
        {
            var csvBytes = await _reportService.DownloadStatUnitEnterprise();
            HttpResponseMessage result = new HttpResponseMessage(HttpStatusCode.OK);
            result.Content = new ByteArrayContent(csvBytes);
            result.Content.Headers.ContentType = new MediaTypeHeaderValue("text/csv");
            result.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment") { FileName = "Export.csv" };
            return MakeResponse(csvBytes, "StatUnitEnterprise.csv");
        }


        [HttpPost]
        [SystemFunction(SystemFunctions.Download)]
        public async Task<HttpResponseMessage> DownloadStatUnitLocalCsv()
        {
            var csvBytes = await _reportService.DownloadStatUnitLocal();
            HttpResponseMessage result = new HttpResponseMessage(HttpStatusCode.OK);
            result.Content = new ByteArrayContent(csvBytes);
            result.Content.Headers.ContentType = new MediaTypeHeaderValue("text/csv");
            result.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment") { FileName = "Export.csv" };
            return MakeResponse(csvBytes, "StatUnitEnterprise.csv");
        }
    }
}
