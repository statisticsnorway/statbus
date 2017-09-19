using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Services;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class LookupController : Controller
    {
        private readonly LookupService _lookupService;

        public LookupController(NSCRegDbContext db)
        {
            _lookupService = new LookupService(db);
        }

        [HttpGet("{lookup}")]
        public async Task<IActionResult> GetLookup(LookupEnum lookup) =>
            Ok(await _lookupService.GetLookupByEnum(lookup).ConfigureAwait(false));

        [HttpGet("paginated/{lookup}")]
        public async Task<IActionResult> GetPaginateLookup(LookupEnum lookup, [FromQuery] SearchLookupModel searchModel) =>
            Ok(await _lookupService.GetPaginateLookupByEnum(lookup, searchModel).ConfigureAwait(false));

        [HttpGet("{lookup}/[action]")]
        public async Task<IActionResult> GetById(LookupEnum lookup, [FromQuery] int[] ids) => Ok(await _lookupService.GetById(lookup, ids));
    }
}
