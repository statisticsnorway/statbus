using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class RegionsController : Controller
    {
        private readonly RegionsService _regionsService;

        public RegionsController(NSCRegDbContext db)
        {
            _regionsService = new RegionsService(db);
        }

        public async Task<IActionResult> List()
        {
            return Ok(await _regionsService.ListAsync());
        }
    }
}
