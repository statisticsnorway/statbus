using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class SectorCodesController: Controller
    {
        private readonly CodeLookupService<SectorCode> _service;

        public SectorCodesController(NSCRegDbContext dbContext)
        {
            _service = new CodeLookupService<SectorCode>(dbContext);
        }

        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard)
        {
            return Ok(await _service.Search(wildcard));
        }
    }
}
