using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Person Controller
    /// </summary>
    [Route("api/[controller]")]
    public class PersonsController : Controller
    {
        private readonly PersonService _service;

        public PersonsController(NSCRegDbContext dbContext)
        {
            _service = new PersonService(dbContext);
        }

        /// <summary>
        /// Person Search Method
        /// </summary>
        /// <param name="wildcard">Search pattern</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));
    }
}
