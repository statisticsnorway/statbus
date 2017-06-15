using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
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
            Ok(await _lookupService.GetLookupOfNonDeleted(lookup).ConfigureAwait(false));
    }
}
