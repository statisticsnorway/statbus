using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class LegalFormsController:Controller
    {
        private readonly CodeLookupService<LegalForm> _service;

        public LegalFormsController(NSCRegDbContext dbContext)
        {
            _service = new CodeLookupService<LegalForm>(dbContext);
        }

        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard)
        {
            return Ok(await _service.Search(wildcard));
        }

        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            return Ok(await _service.GetById(id));
        }
    }
}
