using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class PersonsController : Controller
    {
        private readonly PersonService _service;

        public PersonsController(NSCRegDbContext dbContext)
        {
            _service = new PersonService(dbContext);
        }

        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));
    }
}
