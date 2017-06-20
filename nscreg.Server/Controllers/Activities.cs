using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class ActivitiesController : Controller
    {
        private readonly CodeLookupService<ActivityCategory> _service;

        public ActivitiesController(NSCRegDbContext db)
        {
            _service = new CodeLookupService<ActivityCategory>(db);
        }

        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard)
        {
            return Ok(await _service.Search(wildcard));
        }
    }
}
